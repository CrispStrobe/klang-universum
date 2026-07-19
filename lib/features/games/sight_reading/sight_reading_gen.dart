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

/// Builds a [PlayAlongChart] of [bars] 4/4 bars: an in-key melody that moves
/// mostly by step, starts and ends on the tonic, and never leaves the scale
/// range. Deterministic for a given [seed].
///
/// [stars] (0..3, the player's best tier) scales the difficulty:
///   0 — five-note range (C4–G4), steps only, quarters, gentle 80 BPM;
///   1–2 — full octave (C4–C5), the odd skip, some eighths, 90 BPM;
///   3 — full octave, more skips + the occasional leap, more eighths, 104 BPM.
/// [bpm] overrides the tier's default tempo when given.
PlayAlongChart sightReadingChart(
  int seed, {
  int bars = 4,
  int stars = 1,
  int? bpm,
}) {
  final rng = Random(seed);
  final level = stars.clamp(0, 3);
  final maxDegree =
      level == 0 ? 4 : _cMajorC4.length - 1; // C4–G4 vs full octave
  final allowEighths = level >= 1;
  final eighthOneIn =
      level >= 3 ? 2 : 3; // how often a beat splits into eighths
  final tempo = bpm ?? (level == 0 ? 80 : (level >= 3 ? 104 : 90));

  final totalBeats = bars * 4;
  final notes = <TargetNote>[];
  var idx = 0; // start on the tonic (C4)

  // Stepwise-biased next scale degree, clamped inside the (tier-sized) range.
  // Beginners get steps only; skips and the rare leap appear with the tier.
  int nextDegree() {
    final r = rng.nextInt(12);
    final int delta;
    if (level == 0) {
      delta = r.isEven ? 1 : -1; // steps only
    } else if (r < 7) {
      delta = r.isEven ? 1 : -1; // step
    } else if (r < 10) {
      delta = r.isEven ? 2 : -2; // small skip
    } else if (level >= 3 && r == 11) {
      delta = 3; // an occasional upward leap
    } else {
      delta = 0; // repeat
    }
    return (idx + delta).clamp(0, maxDegree);
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
    // A quarter, or (at higher tiers) a pair of eighths in this beat.
    if (allowEighths && rng.nextInt(eighthOneIn) == 0) {
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
    bpm: tempo,
    notes: notes,
    octaveAgnostic: true, // sung back — the octave is voice-dependent
  );
}
