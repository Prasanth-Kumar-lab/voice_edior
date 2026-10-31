import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class WavData {
  const WavData({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.samples,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final Float64List samples; // interleaved, -1..1

  int get frames => samples.length ~/ max(1, channels);
  int get durationMs => ((frames / sampleRate) * 1000).round();
}

class WavIo {
  WavIo._();

  static Future<WavData> readFile(String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    return decode(bytes);
  }

  static WavData decode(Uint8List bytes) {
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Not a WAV file');
    }
    int offset = 12;
    int sampleRate = 44100;
    int channels = 1;
    int bits = 16;
    int dataStart = 44;
    int dataLen = bytes.length - 44;
    while (offset + 8 <= bytes.length) {
      final String id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final int size = bytes.buffer.asByteData().getUint32(offset + 4, Endian.little);
      offset += 8;
      if (id == 'fmt ') {
        final ByteData fmt = ByteData.sublistView(bytes, offset, offset + size);
        channels = fmt.getUint16(2, Endian.little);
        sampleRate = fmt.getUint32(4, Endian.little);
        bits = fmt.getUint16(14, Endian.little);
      } else if (id == 'data') {
        dataStart = offset;
        dataLen = size;
        break;
      }
      offset += size + (size.isOdd ? 1 : 0);
    }
    final int bytesPer = bits ~/ 8;
    final int count = dataLen ~/ max(1, bytesPer);
    final Float64List samples = Float64List(count);
    final ByteData data = ByteData.sublistView(bytes, dataStart, dataStart + dataLen);
    for (int i = 0; i < count; i++) {
      if (bits == 16) {
        samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
      } else if (bits == 24) {
        final int b0 = bytes[dataStart + i * 3];
        final int b1 = bytes[dataStart + i * 3 + 1];
        final int b2 = bytes[dataStart + i * 3 + 2];
        int v = b0 | (b1 << 8) | (b2 << 16);
        if (v & 0x800000 != 0) v |= 0xFF000000;
        samples[i] = v / 8388608.0;
      } else if (bits == 32) {
        samples[i] = data.getInt32(i * 4, Endian.little) / 2147483648.0;
      } else {
        samples[i] = (bytes[dataStart + i] - 128) / 128.0;
      }
    }
    return WavData(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bits,
      samples: samples,
    );
  }

  static Uint8List encode(WavData wav, {int bits = 16}) {
    final int frames = wav.frames;
    final int block = wav.channels * (bits ~/ 8);
    final int dataLen = frames * block;
    final BytesBuilder out = BytesBuilder(copy: false);
    final ByteData header = ByteData(44);
    void str(int o, String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    header.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, wav.channels, Endian.little);
    header.setUint32(24, wav.sampleRate, Endian.little);
    header.setUint32(28, wav.sampleRate * block, Endian.little);
    header.setUint16(32, block, Endian.little);
    header.setUint16(34, bits, Endian.little);
    str(36, 'data');
    header.setUint32(40, dataLen, Endian.little);
    out.add(header.buffer.asUint8List());
    final ByteData pcm = ByteData(dataLen);
    for (int i = 0; i < wav.samples.length && i < frames * wav.channels; i++) {
      final double s = wav.samples[i].clamp(-1.0, 1.0);
      if (bits == 16) {
        pcm.setInt16(i * 2, (s * 32767).round(), Endian.little);
      } else {
        final int v = (s * 8388607).round();
        pcm.setUint8(i * 3, v & 0xFF);
        pcm.setUint8(i * 3 + 1, (v >> 8) & 0xFF);
        pcm.setUint8(i * 3 + 2, (v >> 16) & 0xFF);
      }
    }
    out.add(pcm.buffer.asUint8List());
    return out.toBytes();
  }

  static Future<void> writeFile(String path, WavData wav, {int bits = 16}) async {
    await File(path).writeAsBytes(encode(wav, bits: bits), flush: true);
  }

  static WavData trim(WavData wav, int startMs, int endMs) {
    final int start = ((startMs / 1000) * wav.sampleRate).round().clamp(0, wav.frames - 1);
    final int end = ((endMs / 1000) * wav.sampleRate).round().clamp(start + 1, wav.frames);
    final int ch = wav.channels;
    return WavData(
      sampleRate: wav.sampleRate,
      channels: ch,
      bitsPerSample: wav.bitsPerSample,
      samples: Float64List.fromList(wav.samples.sublist(start * ch, end * ch)),
    );
  }

  static WavData crop(WavData wav, int startMs, int endMs) => trim(wav, startMs, endMs);

  /// Deletes the selected range [startMs .. endMs] and splices the remaining audio (Audacity Cut / Delete).
  static WavData deleteRange(WavData wav, int startMs, int endMs) {
    final int start = ((startMs / 1000) * wav.sampleRate).round().clamp(0, wav.frames - 1);
    final int end = ((endMs / 1000) * wav.sampleRate).round().clamp(start, wav.frames);
    final int ch = wav.channels;
    final int cutFrames = end - start;
    if (cutFrames <= 0) return wav;
    final int remaining = wav.frames - cutFrames;
    if (remaining <= 0) return trim(wav, 0, min(100, wav.durationMs));
    final Float64List s = Float64List(remaining * ch);
    final int beforeLen = start * ch;
    for (int i = 0; i < beforeLen; i++) {
      s[i] = wav.samples[i];
    }
    final int afterStart = end * ch;
    final int afterLen = (wav.frames - end) * ch;
    for (int i = 0; i < afterLen; i++) {
      s[beforeLen + i] = wav.samples[afterStart + i];
    }
    return WavData(
      sampleRate: wav.sampleRate,
      channels: ch,
      bitsPerSample: wav.bitsPerSample,
      samples: s,
    );
  }

  /// Sets the selected range [startMs .. endMs] to zero amplitude (Audacity Silence Audio).
  static WavData silenceRange(WavData wav, int startMs, int endMs) {
    final int start = ((startMs / 1000) * wav.sampleRate).round().clamp(0, wav.frames - 1);
    final int end = ((endMs / 1000) * wav.sampleRate).round().clamp(start, wav.frames);
    final int ch = wav.channels;
    final Float64List s = Float64List.fromList(wav.samples);
    final int sIdx = start * ch;
    final int eIdx = end * ch;
    for (int i = sIdx; i < eIdx && i < s.length; i++) {
      s[i] = 0.0;
    }
    return WavData(
      sampleRate: wav.sampleRate,
      channels: ch,
      bitsPerSample: wav.bitsPerSample,
      samples: s,
    );
  }

  static WavData fade(WavData wav, {int fadeInMs = 40, int fadeOutMs = 80}) {
    final Float64List s = Float64List.fromList(wav.samples);
    final int ch = wav.channels;
    final int inN = ((fadeInMs / 1000) * wav.sampleRate).round().clamp(1, wav.frames);
    final int outN = ((fadeOutMs / 1000) * wav.sampleRate).round().clamp(1, wav.frames);
    for (int i = 0; i < inN; i++) {
      final double g = i / inN;
      for (int c = 0; c < ch; c++) {
        s[i * ch + c] *= g;
      }
    }
    for (int i = 0; i < outN; i++) {
      final double g = i / outN;
      final int frame = wav.frames - 1 - i;
      for (int c = 0; c < ch; c++) {
        s[frame * ch + c] *= g;
      }
    }
    return WavData(
      sampleRate: wav.sampleRate,
      channels: ch,
      bitsPerSample: wav.bitsPerSample,
      samples: s,
    );
  }

  static WavData normalize(WavData wav, {double target = 0.89}) {
    double peak = 1e-9;
    for (final double v in wav.samples) {
      peak = max(peak, v.abs());
    }
    final double g = target / peak;
    final Float64List s = Float64List(wav.samples.length);
    for (int i = 0; i < s.length; i++) {
      s[i] = (wav.samples[i] * g).clamp(-1.0, 1.0);
    }
    return WavData(
      sampleRate: wav.sampleRate,
      channels: wav.channels,
      bitsPerSample: wav.bitsPerSample,
      samples: s,
    );
  }

  static List<double> peaks(WavData wav, {int bars = 160}) {
    final int ch = wav.channels;
    final int frames = wav.frames;
    if (frames == 0) return List<double>.filled(bars, 0.08);
    final double step = frames / bars;
    return List<double>.generate(bars, (i) {
      final int a = (i * step).floor();
      final int b = min(frames, ((i + 1) * step).ceil());
      double p = 0;
      for (int f = a; f < b; f++) {
        double acc = 0;
        for (int c = 0; c < ch; c++) {
          acc = max(acc, wav.samples[f * ch + c].abs());
        }
        p = max(p, acc);
      }
      return p.clamp(0.04, 1.0);
    });
  }

  static Future<int> durationMs(String path) async {
    try {
      return (await readFile(path)).durationMs;
    } catch (_) {
      return 0;
    }
  }

  static bool looksLikeWav(String path) {
    try {
      final File f = File(path);
      if (!f.existsSync() || f.lengthSync() < 44) return false;
      final RandomAccessFile raf = f.openSync();
      final Uint8List head = raf.readSync(12);
      raf.closeSync();
      return String.fromCharCodes(head.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(head.sublist(8, 12)) == 'WAVE';
    } catch (_) {
      return false;
    }
  }

  /// Last-resort header wrap when FFmpeg cannot decode. Treats payload as
  /// 44.1 kHz mono 16-bit PCM so later edits do not crash.
  static Future<String> wrapRawPcmFile(String input, String out) async {
    final Uint8List bytes = await File(input).readAsBytes();
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE') {
      await File(input).copy(out);
      return out;
    }
    final int count = bytes.length ~/ 2;
    final Float64List samples = Float64List(count);
    final ByteData data = ByteData.sublistView(bytes);
    for (int i = 0; i < count; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    await writeFile(
      out,
      WavData(sampleRate: 44100, channels: 1, bitsPerSample: 16, samples: samples),
    );
    return out;
  }
}
