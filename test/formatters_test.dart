import 'package:flutter_test/flutter_test.dart';
import 'package:voice_edior/models/enhance_mode.dart';
import 'package:voice_edior/utils/formatters.dart';

void main() {
  test('duration formatting', () {
    expect(formatDuration(0), '00:00');
    expect(formatDuration(61000), '01:01');
  });

  test('modes expose their loudness targets', () {
    expect(EnhanceMode.podcast.target, '-16 LUFS');
    expect(EnhanceMode.vocals.target, '-14 LUFS');
    expect(EnhanceMode.vocals.id, 'vocals');
  });
}
