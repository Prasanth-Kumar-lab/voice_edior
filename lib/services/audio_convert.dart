import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Supported export formats in Mix Studio.
enum MixExportFormat {
  wav16('wav_16', 'WAV 16-bit PCM', 'wav', 16),
  wav24('wav_24', 'WAV 24-bit Studio', 'wav', 24),
  wav32f('wav_32f', 'WAV 32-bit Float', 'wav', 32),
  mp3_320('mp3_320', 'MP3 320 kbps', 'mp3', 16),
  mp3_192('mp3_192', 'MP3 192 kbps', 'mp3', 16),
  aac256('aac_256', 'AAC / M4A 256 kbps', 'm4a', 16),
  flac('flac', 'FLAC Lossless', 'flac', 24),
  ogg('ogg', 'OGG Vorbis', 'ogg', 16);

  const MixExportFormat(this.id, this.label, this.extension, this.wavBitDepth);
  final String id;
  final String label;
  final String extension;
  final int wavBitDepth;
}

/// Decodes any imported audio (mp3, m4a, aac, wav, flac, ogg) to mono 48 kHz 16-bit WAV,
/// and encodes rendered WAV masters to MP3/AAC/FLAC/OGG with metadata tags or ZIP stems.
class AudioConvert {
  static Future<String> toWav48(String input) async {
    final Directory dir = await getTemporaryDirectory();
    final String out = p.join(dir.path, 'import-${DateTime.now().millisecondsSinceEpoch}.wav');
    final session = await FFmpegKit.execute(
      '-y -i "${input.replaceAll('\\', '/')}" -vn -ac 1 -ar 48000 -c:a pcm_s16le "$out"',
    );
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc) || !File(out).existsSync() || File(out).lengthSync() < 100) {
      throw StateError('This file could not be decoded.');
    }
    return out;
  }

  /// Creates a loudness-normalized reference copy of the raw recording targeting [targetLufs]
  /// so Original and Enhanced have matching volume for clear A/B comparison without altering
  /// any noise, acoustics, or frequency response.
  static Future<String> createNormalizedOriginal(String inputWav, {double targetLufs = -16.0}) async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final String out = p.join(dir.path, 'orig-norm-${DateTime.now().millisecondsSinceEpoch}.wav');
      final session = await FFmpegKit.execute(
        '-y -i "${inputWav.replaceAll('\\', '/')}" -af "loudnorm=I=${targetLufs.toStringAsFixed(1)}:TP=-1.0" -vn -ac 1 -ar 48000 -c:a pcm_s16le "$out"',
      );
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && File(out).existsSync() && File(out).lengthSync() > 100) {
        return out;
      }
    } catch (_) {}
    return inputWav;
  }

  /// Pre-isolates the vocal using FFmpeg's adaptive FFT Wiener denoiser (afftdn), sub-vocal rumble
  /// high-pass, and ultrasonic/hiss low-pass before the Kotlin/Python harmonic vocal isolator runs.
  static Future<String> preIsolateVocal(
    String inputWav, {
    bool vocalsMode = false,
    double? previewSeconds,
  }) async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final String out = p.join(dir.path, 'pre-iso-${DateTime.now().millisecondsSinceEpoch}.wav');
      final String durArg =
          (previewSeconds != null && previewSeconds > 0) ? '-t ${previewSeconds.toStringAsFixed(1)} ' : '';
      final int lpHz = vocalsMode ? 13000 : 11500;
      final session = await FFmpegKit.execute(
        '-y $durArg-i "${inputWav.replaceAll('\\', '/')}" -af "highpass=f=80:poles=2,afftdn=nf=-25:nr=35:nt=w:tn=1,lowpass=f=$lpHz:poles=2" -vn -ac 1 -ar 48000 -c:a pcm_s16le "$out"',
      );
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && File(out).existsSync() && File(out).lengthSync() > 100) {
        return out;
      }
    } catch (_) {}
    return inputWav;
  }

  /// Transcode a rendered 48 kHz WAV master to [format] with embedded metadata tags
  /// and optional range selection (`trimStartMs` .. `trimEndMs`).
  static Future<String> transcodeMaster({
    required String wavInputPath,
    required MixExportFormat format,
    String title = 'VocalPolish Mix',
    String artist = 'VocalPolish Studio',
    String album = 'VocalPolish Sessions',
    int? trimStartMs,
    int? trimEndMs,
  }) async {
    if (format.extension == 'wav' && trimStartMs == null && trimEndMs == null) {
      return wavInputPath;
    }

    final Directory dir = await getTemporaryDirectory();
    final String outPath = p.join(
      dir.path,
      'export-${DateTime.now().millisecondsSinceEpoch}.${format.extension}',
    );

    final String codecArgs = switch (format) {
      MixExportFormat.wav16 => '-c:a pcm_s16le',
      MixExportFormat.wav24 => '-c:a pcm_s24le',
      MixExportFormat.wav32f => '-c:a pcm_f32le',
      MixExportFormat.mp3_320 => '-c:a libmp3lame -b:a 320k',
      MixExportFormat.mp3_192 => '-c:a libmp3lame -b:a 192k',
      MixExportFormat.aac256 => '-c:a aac -b:a 256k',
      MixExportFormat.flac => '-c:a flac',
      MixExportFormat.ogg => '-c:a libvorbis -q:a 6',
    };

    final StringBuffer trimArgs = StringBuffer();
    if (trimStartMs != null && trimStartMs > 0) {
      trimArgs.write(' -ss ${(trimStartMs / 1000.0).toStringAsFixed(3)}');
    }
    if (trimEndMs != null && trimEndMs > (trimStartMs ?? 0)) {
      final double durSec = (trimEndMs - (trimStartMs ?? 0)) / 1000.0;
      trimArgs.write(' -t ${durSec.toStringAsFixed(3)}');
    }

    final String safeTitle = title.replaceAll('"', '');
    final String safeArtist = artist.replaceAll('"', '');
    final String safeAlbum = album.replaceAll('"', '');

    final String cmd = '-y$trimArgs -i "${wavInputPath.replaceAll('\\', '/')}" '
        '-metadata title="$safeTitle" -metadata artist="$safeArtist" -metadata album="$safeAlbum" '
        '$codecArgs "${outPath.replaceAll('\\', '/')}"';

    try {
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && File(outPath).existsSync() && File(outPath).lengthSync() > 64) {
        return outPath;
      }
    } catch (_) {}

    // Fallback to the source WAV if FFmpeg codec is unavailable in the current environment
    return wavInputPath;
  }

  /// Pure-Dart PKZIP (STORE method 0) archive builder for bundling individual track stem WAVs.
  static Future<String> bundleStemsZip(
    String zipOutputPath,
    Map<String, String> fileNameToSourcePath,
  ) async {
    final BytesBuilder archive = BytesBuilder();
    final BytesBuilder centralDir = BytesBuilder();
    int entryCount = 0;
    int localHeaderOffset = 0;

    for (final MapEntry<String, String> entry in fileNameToSourcePath.entries) {
      final File srcFile = File(entry.value);
      if (!srcFile.existsSync()) continue;
      final Uint8List data = await srcFile.readAsBytes();
      final Uint8List nameBytes = Uint8List.fromList(utf8.encode(entry.key));
      final int crc = _crc32(data);

      // Local file header (30 bytes + filename)
      final ByteData lfh = ByteData(30);
      lfh.setUint32(0, 0x04034b50, Endian.little); // PK\x03\x04
      lfh.setUint16(4, 20, Endian.little); // version needed
      lfh.setUint16(6, 0, Endian.little); // flags
      lfh.setUint16(8, 0, Endian.little); // compression = 0 (STORE)
      lfh.setUint16(10, 0, Endian.little); // mod time
      lfh.setUint16(12, 0x5421, Endian.little); // mod date
      lfh.setUint32(14, crc, Endian.little);
      lfh.setUint32(18, data.length, Endian.little); // compressed size
      lfh.setUint32(22, data.length, Endian.little); // uncompressed size
      lfh.setUint16(26, nameBytes.length, Endian.little);
      lfh.setUint16(28, 0, Endian.little); // extra len

      archive.add(lfh.buffer.asUint8List());
      archive.add(nameBytes);
      archive.add(data);

      // Central directory header (46 bytes + filename)
      final ByteData cdh = ByteData(46);
      cdh.setUint32(0, 0x02014b50, Endian.little); // PK\x01\x02
      cdh.setUint16(4, 20, Endian.little); // version made by
      cdh.setUint16(6, 20, Endian.little); // version needed
      cdh.setUint16(8, 0, Endian.little);
      cdh.setUint16(10, 0, Endian.little); // STORE
      cdh.setUint16(12, 0, Endian.little);
      cdh.setUint16(14, 0x5421, Endian.little);
      cdh.setUint32(16, crc, Endian.little);
      cdh.setUint32(20, data.length, Endian.little);
      cdh.setUint32(24, data.length, Endian.little);
      cdh.setUint16(28, nameBytes.length, Endian.little);
      cdh.setUint16(30, 0, Endian.little);
      cdh.setUint16(32, 0, Endian.little);
      cdh.setUint16(34, 0, Endian.little);
      cdh.setUint16(36, 0, Endian.little);
      cdh.setUint32(38, 0, Endian.little);
      cdh.setUint32(42, localHeaderOffset, Endian.little);

      centralDir.add(cdh.buffer.asUint8List());
      centralDir.add(nameBytes);

      localHeaderOffset += 30 + nameBytes.length + data.length;
      entryCount++;
    }

    final Uint8List cdBytes = centralDir.toBytes();
    archive.add(cdBytes);

    // End of Central Directory record (22 bytes)
    final ByteData eocd = ByteData(22);
    eocd.setUint32(0, 0x06054b50, Endian.little); // PK\x05\x06
    eocd.setUint16(4, 0, Endian.little);
    eocd.setUint16(6, 0, Endian.little);
    eocd.setUint16(8, entryCount, Endian.little);
    eocd.setUint16(10, entryCount, Endian.little);
    eocd.setUint32(12, cdBytes.length, Endian.little);
    eocd.setUint32(16, localHeaderOffset, Endian.little);
    eocd.setUint16(20, 0, Endian.little);
    archive.add(eocd.buffer.asUint8List());

    await File(zipOutputPath).writeAsBytes(archive.toBytes(), flush: true);
    return zipOutputPath;
  }

  static int _crc32(Uint8List bytes) {
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < bytes.length; i++) {
      crc ^= bytes[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc = crc >>> 1;
        }
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
