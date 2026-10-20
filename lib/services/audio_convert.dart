import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Decodes any imported audio (mp3, m4a, aac, wav, …) to mono 48 kHz 16-bit WAV, the engines' native format.
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
}
