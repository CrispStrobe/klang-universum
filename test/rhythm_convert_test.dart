// Converting a quantised rhythm into the app's grid models (Tracker column +
// Loop Mixer drum pattern). Pure, headless — proves a recorded beat re-places
// cleanly onto a target grid regardless of the resolution it was captured at.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/rhythm_convert.dart';
import 'package:comet_beat/core/audio/rhythm_quantize.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart' show TrackerCell;
import 'package:flutter_test/flutter_test.dart';

QuantizedHit _hit(int step, [double strength = 1.0]) => QuantizedHit(
      step: step,
      snappedMs: step * 100.0,
      originalMs: step * 100.0,
      strength: strength,
    );

RhythmQuantization _q(RhythmResolution r, List<int> steps) =>
    RhythmQuantization(r, [for (final s in steps) _hit(s)]);

void main() {
  group('hitToStep re-places by musical position', () {
    test('an eighth-grid hit maps onto coarser and finer grids', () {
      final h = _hit(2); // beat 1.0 on an eighth grid (2 steps/beat)
      expect(hitToStep(h, RhythmResolution.eighth, 1), 1); // quarter grid
      expect(hitToStep(h, RhythmResolution.eighth, 2), 2); // eighth grid
      expect(hitToStep(h, RhythmResolution.eighth, 4), 4); // sixteenth grid
    });

    test('beatOfHit is grid-independent', () {
      expect(beatOfHit(_hit(3), RhythmResolution.sixteenth), 0.75);
      expect(beatOfHit(_hit(2), RhythmResolution.eighth), 1.0);
    });
  });

  group('toTrackerColumn', () {
    test('places a note at each hit step with the given pitch', () {
      final q = _q(RhythmResolution.eighth, [0, 2, 4]);
      final cells = toTrackerColumn(
        q,
        length: 8,
        stepsPerBeat: 2,
        midiOf: (_) => 60,
        instrument: 3,
      );
      expect(cells.length, 8);
      expect(
        [for (final c in cells) c.midi],
        [60, null, 60, null, 60, null, null, null],
      );
      expect(cells[0].instrument, 3);
      // Empty rows stay empty.
      expect(cells[1], TrackerCell.empty);
    });

    test('remaps a quarter-grid capture onto an eighth tracker grid', () {
      final q = _q(RhythmResolution.quarter, [0, 1, 2]); // beats 0,1,2
      final cells =
          toTrackerColumn(q, length: 8, stepsPerBeat: 2, midiOf: (_) => 48);
      // Beats 0/1/2 → eighth rows 0/2/4.
      expect(
        [for (var i = 0; i < 8; i++) cells[i].midi != null],
        [true, false, true, false, true, false, false, false],
      );
    });

    test('hits beyond the pattern length are dropped', () {
      final q = _q(RhythmResolution.eighth, [0, 10]);
      final cells =
          toTrackerColumn(q, length: 4, stepsPerBeat: 2, midiOf: (_) => 60);
      expect(cells.where((c) => c.midi != null).length, 1); // only step 0
    });
  });

  group('toDrumPattern', () {
    test('sets each hit in the row for its drum, on the eighth grid', () {
      final q = _q(RhythmResolution.eighth, [0, 4, 8, 12]);
      final pattern = toDrumPattern(
        q,
        drumOf: (h) => h.step % 8 == 0 ? Drum.kick : Drum.snare,
      );
      expect(pattern.rows[Drum.kick]!.length, kPatternSteps);
      // Steps 0 and 8 → kick; 4 and 12 → snare.
      expect(pattern.rows[Drum.kick]![0], isTrue);
      expect(pattern.rows[Drum.kick]![8], isTrue);
      expect(pattern.rows[Drum.snare]![4], isTrue);
      expect(pattern.rows[Drum.snare]![12], isTrue);
      // Hat untouched.
      expect(pattern.rows[Drum.hat]!.every((b) => !b), isTrue);
    });

    test('a capture longer than the loop wraps by modulo', () {
      // Step 16 == kPatternSteps → wraps to 0.
      final q = _q(RhythmResolution.eighth, [kPatternSteps]);
      final pattern = toDrumPattern(q, drumOf: (_) => Drum.kick);
      expect(pattern.rows[Drum.kick]![0], isTrue);
    });
  });
}
