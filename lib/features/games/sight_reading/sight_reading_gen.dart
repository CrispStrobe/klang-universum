// lib/features/games/sight_reading/sight_reading_gen.dart
//
// Generates endless, never-repeating sight-singing exercises: a fresh in-key
// melody the child reads off the moving score and sings back (mic-graded by the
// existing PlayAlongScreen). Pure + seeded — a given seed always yields the same
// tune (so it is unit-testable), while a new seed each play keeps them varied.

import 'dart:math';

import 'package:comet_beat/core/audio/play_along.dart';

/// The C-major scale from C4 to C5 — a comfortable child vocal range, one letter
/// per scale degree and no accidentals to read at this level.
const List<int> _cMajorC4 = [60, 62, 64, 65, 67, 69, 71, 72];

/// Builds a [PlayAlongChart] of [bars] 4/4 bars at [bpm]: an in-key melody that
/// moves mostly by step (with the odd small skip), starts and ends on the tonic,
/// and never leaves the scale range. Deterministic for a given [seed].
PlayAlongChart sightReadingChart(int seed, {int bars = 4, int bpm = 90}) {
  final rng = Random(seed);
  final totalBeats = bars * 4;
  final notes = <TargetNote>[];
  var idx = 0; // start on the tonic (C4)

  // Stepwise-biased next scale degree: ±1 usually, an occasional ±2, a rare
  // repeat — always clamped inside the scale.
  int nextDegree() {
    final r = rng.nextInt(12);
    final delta = r < 7
        ? (r.isEven ? 1 : -1) // step (7/12)
        : r < 10
            ? (r.isEven ? 2 : -2) // small skip (3/12)
            : 0; // repeat (2/12)
    return (idx + delta).clamp(0, _cMajorC4.length - 1);
  }

  for (var slot = 0; slot < totalBeats; slot++) {
    // Resolve to the tonic on the very last beat.
    if (slot == totalBeats - 1) {
      idx = 0;
      notes.add(
        TargetNote(midi: _cMajorC4[0], startBeat: slot.toDouble(), beats: 1),
      );
      break;
    }
    // A quarter, or (1 in 3) a pair of eighths in this beat.
    if (rng.nextInt(3) == 0) {
      for (var e = 0; e < 2; e++) {
        idx = nextDegree();
        notes.add(
          TargetNote(
            midi: _cMajorC4[idx],
            startBeat: slot + e * 0.5,
            beats: 0.5,
          ),
        );
      }
    } else {
      idx = nextDegree();
      notes.add(
        TargetNote(midi: _cMajorC4[idx], startBeat: slot.toDouble(), beats: 1),
      );
    }
  }

  return PlayAlongChart(
    name: 'Sight-singing',
    bpm: bpm,
    notes: notes,
    octaveAgnostic: true, // sung back — the octave is voice-dependent
  );
}
