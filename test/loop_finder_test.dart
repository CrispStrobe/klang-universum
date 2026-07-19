// Auto-loop-point detection: a periodic sample gets a seamless sustain loop
// (whose length is a whole number of periods), noise/short/silent samples get
// none, and autoLoopedSample builds a looping instrument that sustains. Pure Dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_finder.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A steady sine of exactly [periods] cycles over [n] samples (period = n/periods).
  Float64List sine(int n, int periods, {double amp = 0.8}) {
    final s = Float64List(n);
    for (var i = 0; i < n; i++) {
      s[i] = amp * sin(2 * pi * periods * i / n);
    }
    return s;
  }

  group('findLoopPoints', () {
    test('a periodic tone gets a loop that is a whole number of periods', () {
      const n = 4000, periods = 40; // period = 100 samples
      final lp = findLoopPoints(sine(n, periods));
      expect(lp, isNotNull);
      const period = n / periods; // 100
      // The loop length is a (near-)integer multiple of the period.
      final k = lp!.loopLength / period;
      expect((k - k.roundToDouble()).abs(), lessThan(0.03), reason: 'len=$k·T');
      expect(lp.loopStart, greaterThan(0));
      expect(lp.loopStart + lp.loopLength, lessThanOrEqualTo(n));
    });

    test('the loop is seamless — content repeats across the seam', () {
      const n = 4000, periods = 40;
      final pcm = sine(n, periods);
      final lp = findLoopPoints(pcm)!;
      // pcm[loopStart + w] ≈ pcm[loopStart + loopLength + w]: what plays after
      // the wrap equals what played at the start → no click.
      for (var w = 0; w < 64; w++) {
        expect(
          pcm[lp.loopStart + w],
          closeTo(pcm[lp.loopStart + lp.loopLength + w], 0.03),
          reason: 'seam mismatch at w=$w',
        );
      }
    });

    test('noise has no confident loop → null', () {
      final rng = Random(1);
      final noise = Float64List(4000);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = rng.nextDouble() * 2 - 1;
      }
      expect(findLoopPoints(noise), isNull);
    });

    test('a too-short or silent sample → null', () {
      expect(findLoopPoints(Float64List(100)), isNull); // too short
      expect(findLoopPoints(Float64List(4000)), isNull); // silent
    });
  });

  group('autoLoopedSample', () {
    test('a periodic recording becomes a LOOPING instrument that sustains', () {
      final inst = autoLoopedSample('rec', sine(4000, 40));
      expect(inst.loops, isTrue);

      // A note held far longer than the sample stays audible past the sample's
      // own length (it sustains via the loop instead of falling silent).
      const timing = TrackerTiming(rows: 8, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60),
        ...List<TrackerCell>.filled(7, TrackerCell.empty),
      ];
      final buf = inst.renderChannel(cells, timing);
      final past = inst.sample.length + 20000; // well past the one-shot length
      expect(
        buf.sublist(past, past + 500).any((v) => v.abs() > 1e-3),
        isTrue,
      );
    });

    test('an unloopable sample falls back to a one-shot', () {
      final rng = Random(2);
      final noise = Float64List(4000);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = rng.nextDouble() * 2 - 1;
      }
      expect(autoLoopedSample('n', noise).loops, isFalse);
    });

    test('ping-pong option makes the detected loop bidirectional', () {
      final inst = autoLoopedSample('rec', sine(4000, 40), pingPong: true);
      expect(inst.loops, isTrue);
      expect(inst.pingPong, isTrue);
      // No loop found → pingPong stays false (nothing to bounce).
      final noise = Float64List(300); // too short → no loop
      expect(autoLoopedSample('n', noise, pingPong: true).pingPong, isFalse);
    });
  });
}
