// Loop Mixer 3.0 §B item 3 — style presets. A GrooveStyle re-points the five
// cards at a different pattern set + biases tempo/swing/kit/scale. Every style
// keeps the same ids and stays in C pentatonic (consonant). Pure, headless.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _pentatonic = {0, 2, 4, 7, 9}; // C D E G A

void main() {
  group('every authored style is structurally sound', () {
    test('all styles share the default track ids (state carries across)', () {
      final ids = kLoopMixerTracks.map((t) => t.id).toSet();
      for (final style in kGrooveStyles) {
        expect(
          style.tracks.map((t) => t.id).toSet(),
          ids,
          reason: 'style ${style.id} has different track ids',
        );
      }
    });

    test('every variant of every track fills the loop and renders audio', () {
      for (final bpm in [75, 100, 120]) {
        final timing = LoopTiming(tempoBpm: bpm);
        for (final style in kGrooveStyles) {
          for (final track in style.tracks) {
            for (var v = 0; v < track.variants.length; v++) {
              final stem = track.variants[v].render(timing);
              expect(
                stem.length,
                timing.totalSamples,
                reason: '${style.id}/${track.id}[$v] @ $bpm length',
              );
              expect(
                stem.any((s) => s.abs() > 1e-6),
                isTrue,
                reason: '${style.id}/${track.id}[$v] silent',
              );
            }
          }
        }
      }
    });

    test('every pitched note stays in C pentatonic (consonance guarantee)', () {
      for (final style in kGrooveStyles) {
        for (final track in style.tracks) {
          for (final pattern in track.variants) {
            if (pattern is! MelodicPattern) continue;
            for (final cell in pattern.cells) {
              for (final m in cell.midis ?? const <int>[]) {
                expect(
                  _pentatonic.contains(m % 12),
                  isTrue,
                  reason: '${style.id}/${track.id}: $m off-pentatonic',
                );
              }
            }
          }
        }
      }
    });
  });

  group('selecting a style swaps the band and biases the feel', () {
    test('the render changes but enabled/variant state carries by id', () {
      final e = LoopEngine()
        ..enabled.addAll({'drums', 'bass'})
        ..variants['drums'] = 1;
      final before = e.renderLoop();

      e.styleId = 'four';
      expect(e.styleId, 'four');
      expect(e.enabled, {'drums', 'bass'}); // preserved
      expect(e.variants['drums'], 1); // preserved
      expect(e.renderLoop(), isNot(equals(before))); // different patterns
    });

    test('a style applies its tempo/swing/kit/scale bias', () {
      final e = LoopEngine()..styleId = 'chill';
      expect(e.tempoBpm, 75);
      expect(e.swing, closeTo(0.33, 1e-9));
      expect(e.kitId, 'lofi');

      final f = LoopEngine()..styleId = 'four';
      expect(f.tempoBpm, 120);
      expect(f.kitId, 'deep');
    });

    test('an unknown style id falls back to default', () {
      final e = LoopEngine()..styleId = 'nope';
      expect(e.styleId, 'default');
    });
  });

  group('share token', () {
    test('style id roundtrips; default is omitted', () {
      expect(
        const GrooveSpec(enabled: {'drums'}).toJson().containsKey('st'),
        isFalse,
      );
      const spec = GrooveSpec(enabled: {'drums'}, styleId: 'chill');
      expect(spec.toJson()['st'], 'chill');
      expect(GrooveSpec.fromJson(spec.toJson()).styleId, 'chill');
    });

    test('applySpec restores the style AND the exact saved tempo (not bias)',
        () {
      // 'four' biases tempo to 120, but the saved spec pinned 100 → 100 wins.
      const spec = GrooveSpec(
        enabled: {'drums'},
        styleId: 'four',
      );
      final e = LoopEngine()..applySpec(spec);
      expect(e.styleId, 'four');
      expect(e.tempoBpm, 100);
      // A full round-trip preserves the style.
      expect(e.spec.styleId, 'four');
    });
  });
}
