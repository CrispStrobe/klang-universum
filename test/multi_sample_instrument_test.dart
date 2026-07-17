// test/multi_sample_instrument_test.dart
//
// The XM/IT-style keymap instrument (TRACKER_IDEAS §B): a sample per note-range.
// Two things to prove — (1) zone SELECTION (covers / nearest fallback / the
// mapped() auto-ranging), and (2) that renderChannel actually plays the CHOSEN
// zone's sample for each note-run (a low note reads the low zone, a high note
// the high zone).
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/multi_sample_instrument_test.dart

import 'dart:typed_data';

import 'package:comet_beat/core/audio/multi_sample_instrument.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _flat(double v, int n) => Float64List(n)..fillRange(0, n, v);

void main() {
  group('zoneFor — selection', () {
    // mapped() splits at the midpoint between adjacent base notes.
    final inst = MultiSampleInstrument.mapped('t', [
      (sample: _flat(0.5, 8), baseMidi: 48),
      (sample: _flat(-0.5, 8), baseMidi: 72),
    ]);

    test('midpoint 60 → the two zones cover 0..60 and 61..127', () {
      expect(inst.zones.length, 2);
      expect(inst.zones[0].loMidi, 0);
      expect(inst.zones[0].hiMidi, 60);
      expect(inst.zones[1].loMidi, 61);
      expect(inst.zones[1].hiMidi, 127);
    });

    test('covering zone wins', () {
      expect(inst.zoneFor(48)!.baseMidi, 48);
      expect(inst.zoneFor(60)!.baseMidi, 48);
      expect(inst.zoneFor(61)!.baseMidi, 72);
      expect(inst.zoneFor(100)!.baseMidi, 72);
    });

    test('empty instrument → null', () {
      expect(const MultiSampleInstrument('e', []).zoneFor(60), isNull);
    });

    test('nearest-base fallback when no zone covers', () {
      // A single narrow zone; notes outside it fall back to it (only choice).
      final narrow = MultiSampleInstrument('n', [
        SampleZone(sample: _flat(0.5, 8), baseMidi: 60, loMidi: 59, hiMidi: 61),
      ]);
      expect(narrow.zoneFor(12)!.baseMidi, 60);
      expect(narrow.zoneFor(120)!.baseMidi, 60);
    });
  });

  group('mapped — auto key-ranges are contiguous and gapless', () {
    test('three points → 0..46, 47..58, 59..127', () {
      final inst = MultiSampleInstrument.mapped('t', [
        (sample: _flat(0.1, 8), baseMidi: 40),
        (sample: _flat(0.2, 8), baseMidi: 52),
        (sample: _flat(0.3, 8), baseMidi: 64),
      ]);
      expect(inst.zones.map((z) => [z.loMidi, z.hiMidi]), [
        [0, 46],
        [47, 58],
        [59, 127],
      ]);
      // no gaps: every MIDI note resolves to a zone
      for (var m = 0; m <= 127; m++) {
        expect(inst.zoneFor(m), isNotNull);
      }
    });

    test('unsorted points are sorted by baseMidi', () {
      final inst = MultiSampleInstrument.mapped('t', [
        (sample: _flat(0.3, 8), baseMidi: 64),
        (sample: _flat(0.1, 8), baseMidi: 40),
      ]);
      expect(inst.zones.map((z) => z.baseMidi), [40, 64]);
    });
  });

  group('renderChannel — the chosen zone is what plays', () {
    // Zone A = a +0.5 plateau at MIDI 48; zone B = a −0.5 plateau at MIDI 72.
    // Played at each base note (ratio 1, no resample), the rendered run should
    // carry that zone's sign — proving selection reaches the audio.
    const len = 8000;
    final inst = MultiSampleInstrument.mapped('kit', [
      (sample: _flat(0.5, len), baseMidi: 48),
      (sample: _flat(-0.5, len), baseMidi: 72),
    ]);
    const timing =
        TrackerTiming(); // 120bpm, 16 rows, 4 steps/beat → 125ms/step

    test('low note reads zone A (+), high note reads zone B (−)', () {
      final cells = List<TrackerCell>.generate(16, (i) {
        if (i == 0) return const TrackerCell(midi: 48); // zone A
        if (i == 8) return const TrackerCell(midi: 72); // zone B
        return TrackerCell.empty;
      });
      final out = inst.renderChannel(cells, timing);

      // Step 8 onset = 8 * 125ms = 1000ms = 44100 samples. Sample each run past
      // the declick attack, before its release.
      final aMid = out[1000]; // inside run 0 (steps 0..7)
      final bMid = out[44100 + 1000]; // inside run 1 (steps 8..15)
      expect(aMid, closeTo(0.5, 0.02), reason: 'low run plays the +0.5 zone');
      expect(bMid, closeTo(-0.5, 0.02), reason: 'high run plays the −0.5 zone');
    });

    test('empty instrument renders silence of the right length', () {
      final out = const MultiSampleInstrument('e', [])
          .renderChannel([const TrackerCell(midi: 60)], timing);
      expect(out.length, timing.totalSamples);
      expect(out.every((v) => v == 0), isTrue);
    });
  });
}
