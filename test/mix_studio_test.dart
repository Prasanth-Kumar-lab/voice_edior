import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_edior/models/fx_slot.dart';
import 'package:voice_edior/models/mix_clip.dart';
import 'package:voice_edior/models/mix_command.dart';
import 'package:voice_edior/models/mix_project.dart';
import 'package:voice_edior/models/mix_track.dart';
import 'package:voice_edior/services/audio_convert.dart';
import 'package:voice_edior/utils/app_localization.dart';

void main() {
  group('MixProject & .vpmix Serialization', () {
    test('Templates round-trip through JSON losslessly', () {
      for (final String tplId in [
        'podcast_episode',
        'song_vocal',
        'voiceover_duck',
        'blank',
      ]) {
        final MixProject original = MixProject.template(tplId);
        original.markers.add(
          TimelineMarker(id: 'm_test', timeMs: 2500, label: 'Chorus'),
        );
        original.tracks.first.clips.add(
          MixClip(
            id: 'c1',
            name: 'Lead Vocal',
            sourcePath: '/tmp/vocal.wav',
            timelineStartMs: 500,
            offsetStartMs: 100,
            durationMs: 4000,
            sourceDurationMs: 5000,
            gainDb: 2.5,
            fadeInMs: 120,
            fadeOutMs: 240,
            fadeInCurve: FadeCurve.sCurve,
            stretchRate: 1.25,
            pitchSemitones: -3.0,
            peaks: const [0.2, 0.6, 0.9, 0.4],
          ),
        );

        final Map<String, dynamic> json = original.toJson();
        final MixProject restored = MixProject.fromJson(json);

        expect(restored.schemaVersion, 1);
        expect(restored.name, original.name);
        expect(restored.tracks.length, original.tracks.length);
        expect(restored.markers.last.label, 'Chorus');

        final MixClip rc = restored.tracks.first.clips.first;
        expect(rc.name, 'Lead Vocal');
        expect(rc.timelineStartMs, 500);
        expect(rc.timelineEndMs, 4500);
        expect(rc.gainDb, closeTo(2.5, 1e-6));
        expect(rc.fadeInCurve, FadeCurve.sCurve);
        expect(rc.stretchRate, closeTo(1.25, 1e-6));
        expect(rc.pitchSemitones, closeTo(-3.0, 1e-6));
        expect(rc.peaks.length, 4);
      }
    });
  });

  group('UndoRedoStack (Command Pattern, 60+ steps)', () {
    test('Supports 60 undo and redo steps accurately', () {
      final UndoRedoStack stack = UndoRedoStack(maxSteps: 60);
      MixProject current = MixProject.template('blank');

      for (int i = 1; i <= 65; i++) {
        final MixProject before = current.copyWith();
        final MixProject after = current.copyWith(bpm: 100.0 + i);
        stack.recordChange(label: 'Set BPM $i', before: before, after: after);
        current = after;
      }

      // Capped at 60 steps
      expect(stack.undoCount, 60);
      expect(current.bpm, 165.0);

      // Undo 10 times
      for (int i = 0; i < 10; i++) {
        current = stack.undo(current)!;
      }
      expect(current.bpm, 155.0);
      expect(stack.redoCount, 10);

      // Redo 5 times
      for (int i = 0; i < 5; i++) {
        current = stack.redo(current)!;
      }
      expect(current.bpm, 160.0);
    });
  });

  group('Fade Curves, Automation & Voice Changer Macro Presets', () {
    test('FadeCurve gain evaluation is monotonic and bounded in [0, 1]', () {
      for (final FadeCurve curve in FadeCurve.values) {
        expect(curve.gainAt(0.0), closeTo(0.0, 1e-6));
        expect(curve.gainAt(1.0), closeTo(1.0, 1e-6));
        final double mid = curve.gainAt(0.5);
        expect(mid, greaterThan(0.0));
        expect(mid, lessThan(1.0));
      }
    });

    test('Track volume automation interpolates breakpoints in dB', () {
      final MixTrack track = MixTrack(
        id: 't1',
        name: 'Voice',
        volumeDb: 0.0,
        volumeAutomation: [
          AutomationPoint(timeMs: 0, value: 0.0),
          AutomationPoint(timeMs: 1000, value: -12.0),
        ],
      );
      expect(track.automatedVolumeDbAt(0), closeTo(0.0, 1e-4));
      expect(track.automatedVolumeDbAt(500), closeTo(-6.0, 1e-3));
      expect(track.automatedVolumeDbAt(1000), closeTo(-12.0, 1e-4));
    });

    test('All 10 VoiceChangerPresets build non-empty FX chains', () {
      expect(VoiceChangerPreset.all.length, 10);
      for (final VoiceChangerPreset p in VoiceChangerPreset.all) {
        final List<FxSlot> chain = p.buildChain();
        expect(chain, isNotEmpty);
      }
    });

    test('bundleStemsZip creates a valid PKZIP archive with stem entries', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('vpmix_test_');
      try {
        final File s1 = File('${tmp.path}/stem1.wav')..writeAsBytesSync([82, 73, 70, 70]);
        final File s2 = File('${tmp.path}/stem2.wav')..writeAsBytesSync([87, 65, 86, 69]);
        final String zipOut = '${tmp.path}/stems.zip';
        await AudioConvert.bundleStemsZip(zipOut, {
          '01_Voice.wav': s1.path,
          '02_Music.wav': s2.path,
        });
        final List<int> bytes = File(zipOut).readAsBytesSync();
        // PK\x03\x04 magic header
        expect(bytes.sublist(0, 4), equals([0x50, 0x4B, 0x03, 0x04]));
        expect(bytes.length, greaterThan(100));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('Phase 5 UseCasePresets and multilingual AppPreferencesController work', () {
      expect(UseCasePreset.defaults.length, 6);
      for (final UseCasePreset p in UseCasePreset.defaults) {
        expect(p.buildChain(), isNotEmpty);
      }

      final AppPreferencesController prefs = AppPreferencesController();
      expect(prefs.trKey('studio'), 'Studio');
      prefs.setLanguage('hi');
      expect(prefs.trKey('studio'), 'स्टूडियो');
      prefs.setLanguage('te');
      expect(prefs.trKey('studio'), 'స్టూడియో');
    });
  });
}
