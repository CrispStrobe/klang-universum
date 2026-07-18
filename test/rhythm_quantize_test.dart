// The beginner rhythm "Relevanzschwelle" engine — pure, headless. Verifies the
// auto-resolution picker (coarsest grid the player can feel, capped by skill),
// snapping, same-step collapse, the strength threshold, and onset detection.

import 'package:comet_beat/core/audio/rhythm_quantize.dart';
import 'package:flutter_test/flutter_test.dart';

// 120 bpm → 500 ms/beat; an eighth = 250 ms, a sixteenth = 125 ms.
const _beatMs = 500.0;

RhythmOnset _on(double ms, [double strength = 1.0]) =>
    (ms: ms, strength: strength);

void main() {
  group('stepsPerBeat', () {
    test('maps each subdivision', () {
      expect(RhythmResolution.quarter.stepsPerBeat, 1);
      expect(RhythmResolution.eighth.stepsPerBeat, 2);
      expect(RhythmResolution.tripletEighth.stepsPerBeat, 3);
      expect(RhythmResolution.sixteenth.stepsPerBeat, 4);
    });
  });

  group('chooseResolution (the auto threshold)', () {
    test('clean quarter-note taps settle on the quarter grid', () {
      final onsets = [0.0, 500.0, 1000.0, 1500.0];
      expect(
        chooseResolution(
          onsets,
          beatMs: _beatMs,
          cap: RhythmResolution.sixteenth,
        ),
        RhythmResolution.quarter,
      );
    });

    test('a loose (±40 ms) quarter feel is NOT over-quantised', () {
      final onsets = [0.0, 540.0, 980.0, 1460.0]; // sloppy, still quarters
      expect(
        chooseResolution(
          onsets,
          beatMs: _beatMs,
          cap: RhythmResolution.sixteenth,
        ),
        RhythmResolution.quarter,
      );
    });

    test('an off-beat eighth forces the eighth grid, not quarter', () {
      final onsets = [0.0, 250.0, 500.0]; // a note on the "and"
      expect(
        chooseResolution(
          onsets,
          beatMs: _beatMs,
          cap: RhythmResolution.sixteenth,
        ),
        RhythmResolution.eighth,
      );
    });

    test('real sixteenths choose the sixteenth grid when allowed', () {
      final onsets = [0.0, 125.0, 250.0, 375.0];
      expect(
        chooseResolution(
          onsets,
          beatMs: _beatMs,
          cap: RhythmResolution.sixteenth,
        ),
        RhythmResolution.sixteenth,
      );
    });

    test('eighth-note triplets choose the triplet grid', () {
      const third = 500.0 / 3;
      final onsets = [0.0, third, 2 * third, 500.0];
      expect(
        chooseResolution(
          onsets,
          beatMs: _beatMs,
          cap: RhythmResolution.sixteenth,
        ),
        RhythmResolution.tripletEighth,
      );
    });

    test('the skill cap stops a beginner resolving finer than eighths', () {
      final onsets = [0.0, 125.0, 250.0, 375.0]; // played as sixteenths
      expect(
        chooseResolution(onsets, beatMs: _beatMs),
        RhythmResolution.eighth,
      );
    });

    test('a single onset is the coarsest grid', () {
      expect(
        chooseResolution(
          [0.0],
          beatMs: _beatMs,
          cap: RhythmResolution.sixteenth,
        ),
        RhythmResolution.quarter,
      );
    });
  });

  group('quantizeRhythm', () {
    test('snaps onsets to the chosen grid and reports the resolution', () {
      final q = quantizeRhythm(
        [_on(10), _on(255), _on(495)], // near 0, eighth, quarter
        beatMs: _beatMs,
        cap: RhythmResolution.sixteenth,
      );
      expect(q.resolution, RhythmResolution.eighth);
      expect(q.hits.map((h) => h.step).toList(), [0, 1, 2]);
      expect(q.hits.map((h) => h.snappedMs).toList(), [0.0, 250.0, 500.0]);
    });

    test('the beginner cap collapses sixteenth flams onto one eighth', () {
      final q = quantizeRhythm(
        [_on(0), _on(120, 0.4), _on(250)], // 0 + a near flam + the "and"
        beatMs: _beatMs,
      );
      expect(q.resolution, RhythmResolution.eighth);
      // 0 and 120 both snap to step 0 → collapse; the "and" is step 1.
      expect(q.hits.map((h) => h.step).toList(), [0, 1]);
      // The stronger of the two collapsed hits (the downbeat) is kept.
      expect(q.hits.first.strength, 1.0);
    });

    test('sub-strength onsets are dropped as noise', () {
      final q = quantizeRhythm(
        [_on(0, 0.9), _on(250, 0.05), _on(500, 0.8)],
        beatMs: _beatMs,
        minStrength: 0.2,
      );
      expect(q.hits.map((h) => h.step).toList(), [0, 1]); // the weak "and" gone
      expect(q.hits.map((h) => h.snappedMs).toList(), [0.0, 500.0]);
    });

    test('empty / degenerate input yields an empty result', () {
      expect(quantizeRhythm([], beatMs: _beatMs).hits, isEmpty);
      expect(quantizeRhythm([_on(0)], beatMs: 0).hits, isEmpty);
    });
  });

  group('detectOnsets', () {
    test('finds one onset per energy bump, with a refractory window', () {
      // Three loud bumps over a dense, mostly-quiet trace (each hit is preceded
      // by a quiet frame, as a real ~10-20 ms capture is).
      final frames = <EnergyFrame>[
        (ms: 0, rms: 0.005),
        (ms: 20, rms: 0.30), // bump 1
        (ms: 40, rms: 0.35),
        (ms: 60, rms: 0.006),
        (ms: 240, rms: 0.006),
        (ms: 260, rms: 0.40), // bump 2 (past refractory)
        (ms: 280, rms: 0.20),
        (ms: 500, rms: 0.005),
        (ms: 520, rms: 0.33), // bump 3
        (ms: 540, rms: 0.10),
      ];
      final onsets = detectOnsets(frames);
      expect(onsets.map((o) => o.ms).toList(), [20.0, 260.0, 520.0]);
      // Strength is the peak across the attack (bump 1 peaks at 0.35).
      expect(onsets.first.strength, 0.35);
    });

    test('a quiet trace has no onsets', () {
      final frames = <EnergyFrame>[
        (ms: 0, rms: 0.004),
        (ms: 20, rms: 0.006),
        (ms: 40, rms: 0.005),
      ];
      expect(detectOnsets(frames), isEmpty);
    });
  });

  test('detect → quantise end to end (tapped quarter notes)', () {
    // Four evenly-spaced taps at ~120 bpm, each a short attack.
    final frames = <EnergyFrame>[
      for (var beat = 0; beat < 4; beat++) ...[
        (ms: beat * 500.0, rms: 0.30),
        (ms: beat * 500.0 + 20, rms: 0.10),
      ],
    ];
    final onsets = detectOnsets(frames);
    final q = quantizeRhythm(
      onsets,
      beatMs: _beatMs,
      cap: RhythmResolution.sixteenth,
    );
    expect(q.resolution, RhythmResolution.quarter);
    expect(q.hits.map((h) => h.step).toList(), [0, 1, 2, 3]);
  });
}
