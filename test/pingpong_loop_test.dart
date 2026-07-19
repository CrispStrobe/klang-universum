// Ping-pong (bidirectional) sample loops: the pure fold helper bounces
// correctly, a ping-pong SampleInstrument renders differently from a forward
// one, and the IT bidi flag flows through the import bridge. Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_instrument_bridge.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('foldLoopPosition', () {
    // Loop region [10, 18): loopStart 10, loopLen 8, loopEnd 18.
    const start = 10, len = 8;
    double fwd(double p) => foldLoopPosition(p, start, len, pingPong: false);
    double pp(double p) => foldLoopPosition(p, start, len, pingPong: true);

    test('before the loop end both are the position unchanged (lead-in)', () {
      for (final p in [0.0, 5.0, 12.0, 17.9]) {
        expect(fwd(p), p);
        expect(pp(p), p);
      }
    });

    test('a forward loop wraps (sawtooth)', () {
      expect(fwd(18), 10); // wrap to loopStart
      expect(fwd(19), 11);
      expect(fwd(25), 10 + (25 - 10) % 8); // == 10 + 7 = 17
      expect(fwd(26), 10); // full wrap again
    });

    test('a ping-pong loop bounces (triangle)', () {
      // Backward leg: 18 → 10 as pos goes 18 → 26.
      expect(pp(18), 18); // turn point (== loopEnd)
      expect(pp(19), 17);
      expect(pp(22), 14);
      expect(pp(26), 10); // reached loopStart
      // Forward leg again: 10 → 18 as pos goes 26 → 34.
      expect(pp(27), 11);
      expect(pp(30), 14);
      expect(pp(34), 18);
    });

    test('the two modes diverge past the loop end', () {
      expect(fwd(19), isNot(pp(19))); // 11 vs 17
      expect(fwd(21), isNot(pp(21))); // 13 vs 15
    });

    test('a fractional position folds smoothly (interpolatable)', () {
      // Just past the turn, the ping-pong position decreases fractionally.
      expect(pp(18.5), closeTo(17.5, 1e-9));
      expect(pp(19.25), closeTo(16.75, 1e-9));
    });
  });

  group('SampleInstrument ping-pong render', () {
    // A rising ramp; the loop region repeats it. Forward = sawtooth, ping-pong
    // = triangle → the rendered audio differs.
    Float64List ramp(int n) {
      final s = Float64List(n);
      for (var i = 0; i < n; i++) {
        s[i] = i / n; // 0 → ~1
      }
      return s;
    }

    // baseMidi defaults to 60, so a midi-60 note plays at ratio 1 (1:1 read).
    SampleInstrument inst({required bool pingPong}) => SampleInstrument(
          'ramp',
          ramp(20),
          envelope: Envelope.none, // no attack shaping — read the ramp directly
          loopStart: 10,
          loopLength: 8,
          pingPong: pingPong,
        );

    test('forward vs ping-pong render differently (bounce changes the sound)',
        () {
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60), // plays at ratio 1 (baseMidi)
        ...List<TrackerCell>.filled(3, TrackerCell.empty),
      ];
      final fwd = inst(pingPong: false).renderChannel(cells, timing);
      final pp = inst(pingPong: true).renderChannel(cells, timing);
      expect(fwd.any((v) => v != 0), isTrue);
      expect(pp.any((v) => v != 0), isTrue);
      // Same length, but the loop content differs → not byte-identical.
      expect(pp, isNot(fwd));
    });

    test('a non-looping sample is unaffected by the flag (byte-identical)', () {
      // loopLength 0 → one-shot; pingPong is irrelevant → identical renders.
      const timing = TrackerTiming(rows: 2, stepsPerBeat: 2);
      final cells = [const TrackerCell(midi: 60), TrackerCell.empty];
      final a = SampleInstrument('r', ramp(20)).renderChannel(cells, timing);
      final b = SampleInstrument('r', ramp(20), pingPong: true)
          .renderChannel(cells, timing);
      expect(b, a);
    });
  });

  group('import bridge', () {
    test('DocSample.pingPong flows into SampleInstrument.pingPong', () {
      final pcm = Float64List(40);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
      }
      final bidi = DocSample(
        pcm: pcm,
        loopStart: 8,
        loopLength: 16,
        pingPong: true,
      );
      expect(sampleInstrumentFromDoc('s', bidi).pingPong, isTrue);

      final fwd = DocSample(pcm: pcm, loopStart: 8, loopLength: 16);
      expect(sampleInstrumentFromDoc('s', fwd).pingPong, isFalse);
    });
  });
}
