// Loop Mixer 3.0 §B item 2 — swappable drum kits. A DrumKit changes the drum
// TIMBRE (tune/decay/noise/sweep/crush) but never the onset grid. Pure,
// headless: buffer-length invariance + measurable timbre shifts + token.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

int _zeroCrossings(Float64List b) {
  var c = 0;
  for (var i = 1; i < b.length; i++) {
    if ((b[i - 1] < 0) != (b[i] < 0)) c++;
  }
  return c;
}

double _energy(Float64List b, int from, int to) {
  var e = 0.0;
  for (var i = from; i < to; i++) {
    e += b[i] * b[i];
  }
  return e;
}

const _deep =
    DrumKit('deep', tune: 0.80, decay: 0.62, noise: 0.82, sweep: 1.30);

void main() {
  group('the kit changes timbre, not timing', () {
    test('every voice keeps the same buffer length across kits (grid-safe)',
        () {
      for (final drum in Drum.values) {
        final clean = renderDrum(drum);
        for (final kit in kDrumKits) {
          expect(
            renderDrum(drum, kit: kit).length,
            clean.length,
            reason: '$drum length changed under ${kit.id}',
          );
        }
      }
    });

    test('a pattern places hits at identical sample positions across kits', () {
      final List<(int, Drum)> hits = [
        (0, Drum.kick),
        (250, Drum.snare),
      ];
      final clean = renderDrumPattern(hits, totalMs: 1000);
      final deep = renderDrumPattern(hits, totalMs: 1000, kit: _deep);
      expect(deep.length, clean.length);
      // The first non-zero sample (the downbeat kick) starts at index 0 in both.
      expect(clean[0] != 0 || clean[1] != 0, isTrue);
      expect(deep[0] != 0 || deep[1] != 0, isTrue);
      // The snare hit begins at the same sample (250 ms) in both renders.
      const snareStart = 250 * kSampleRate ~/ 1000;
      expect(clean[snareStart - 1], 0);
      expect(deep[snareStart - 1], 0);
      expect(clean[snareStart] != 0, isTrue);
      expect(deep[snareStart] != 0, isTrue);
    });
  });

  group('the kit audibly changes the sound', () {
    test('a lower tune lowers the kick pitch (fewer zero crossings)', () {
      final clean = renderDrum(Drum.kick);
      final deep = renderDrum(Drum.kick, kit: _deep); // tune 0.80
      expect(_zeroCrossings(deep), lessThan(_zeroCrossings(clean)));
    });

    test('a shorter decay rate sustains longer (more late energy)', () {
      final clean = renderDrum(Drum.kick); // decay 1.0
      final deep = renderDrum(Drum.kick, kit: _deep); // decay 0.62
      final half = clean.length ~/ 2;
      // Unit-peak normalized, so compare the tail's share of energy.
      final cleanLate = _energy(clean, half, clean.length);
      final deepLate = _energy(deep, half, deep.length);
      expect(deepLate, greaterThan(cleanLate));
    });

    test('every non-clean kit renders a different buffer', () {
      for (final kit in kDrumKits.where((k) => k.id != 'clean')) {
        expect(
          renderDrum(Drum.snare, kit: kit),
          isNot(equals(renderDrum(Drum.snare))),
          reason: '${kit.id} snare identical to clean',
        );
      }
    });
  });

  group('engine wiring: the kit swaps every drum path', () {
    LoopEngine drumsEngine() =>
        LoopEngine()..applySpec(const GrooveSpec(enabled: {'drums'}));

    test('changing the kit re-renders the loop (incl. the fill path)', () {
      final e = drumsEngine();
      final clean = e.renderLoop();
      final cleanFill = e.renderLoop(fill: true);
      e.kitId = 'deep';
      expect(e.renderLoop(), isNot(equals(clean)));
      expect(e.renderLoop(fill: true), isNot(equals(cleanFill)));
    });

    test('an unknown kit id falls back to clean', () {
      final e = drumsEngine()..kitId = 'nope';
      expect(e.kitId, 'clean');
      expect(e.renderLoop(), equals(drumsEngine().renderLoop()));
    });
  });

  group('share token', () {
    test('kit id roundtrips; default is omitted', () {
      expect(
        const GrooveSpec(enabled: {'drums'}).toJson().containsKey('kt'),
        isFalse,
      );
      const spec = GrooveSpec(enabled: {'drums'}, kitId: 'lofi');
      expect(spec.toJson()['kt'], 'lofi');
      expect(GrooveSpec.fromJson(spec.toJson()).kitId, 'lofi');
    });

    test('cacheKey changes with the kit', () {
      const a = GrooveSpec(enabled: {'drums'});
      const b = GrooveSpec(enabled: {'drums'}, kitId: 'warm');
      expect(a.cacheKey, isNot(b.cacheKey));
    });
  });
}
