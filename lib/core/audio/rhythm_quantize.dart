// lib/core/audio/rhythm_quantize.dart
//
// The beginner rhythm "Relevanzschwelle" (relevance threshold) engine: turns a
// captured performance into quantised note steps on the grid the player can
// actually FEEL. It (1) finds onsets in an energy trace, (2) auto-picks the
// coarsest metric subdivision that explains those onsets — so a beginner's loose
// eighth-note playing is NOT over-quantised to sixteenths — never finer than a
// skill cap, (3) snaps each onset to that grid, and (4) applies the relevance
// threshold: drops sub-strength hits and collapses hits that land on the same
// step. Pure Dart, headless-testable. This is the shared front-end that later
// slices convert to Tracker cells / GrooveSpec / a Score / MIDI.
//
// Complements the drum-specific `beat_capture.quantizeToBeat` (which is pinned
// to a fixed eighth grid); this is the general, skill-tiered core.

/// A metric subdivision of the beat — how finely a rhythm is felt.
enum RhythmResolution {
  /// One step per quarter-note beat (♩).
  quarter,

  /// Two steps per beat (♪ eighths).
  eighth,

  /// Three steps per beat (eighth-note triplets).
  tripletEighth,

  /// Four steps per beat (𝅘𝅥𝅯 sixteenths).
  sixteenth,
}

/// Grid maths for a [RhythmResolution].
extension RhythmResolutionX on RhythmResolution {
  /// Grid steps per quarter-note beat.
  int get stepsPerBeat => switch (this) {
        RhythmResolution.quarter => 1,
        RhythmResolution.eighth => 2,
        RhythmResolution.tripletEighth => 3,
        RhythmResolution.sixteenth => 4,
      };
}

/// The order the auto-picker tries subdivisions — coarsest (simplest to feel)
/// first, so the loosest grid that still fits wins.
const _ladder = [
  RhythmResolution.quarter,
  RhythmResolution.eighth,
  RhythmResolution.tripletEighth,
  RhythmResolution.sixteenth,
];

/// Milliseconds per quarter-note beat at [bpm].
double beatMsFromBpm(double bpm) => 60000.0 / bpm;

/// One captured onset: when it happened (ms from capture start) and how strong
/// the hit was (peak energy; use 1.0 if you don't track strength).
typedef RhythmOnset = ({double ms, double strength});

/// One raw capture frame: elapsed ms and energy (rms).
typedef EnergyFrame = ({double ms, double rms});

/// A single quantised note: which grid [step] it snapped to (0-based), the grid
/// time it now sits at, where it originally landed, and its strength.
class QuantizedHit {
  /// Creates a quantised hit.
  const QuantizedHit({
    required this.step,
    required this.snappedMs,
    required this.originalMs,
    required this.strength,
  });

  /// The 0-based grid step the onset snapped to.
  final int step;

  /// The grid time (ms) the note now sits at.
  final double snappedMs;

  /// Where the onset originally landed (ms).
  final double originalMs;

  /// The hit's strength (peak energy).
  final double strength;

  @override
  bool operator ==(Object other) =>
      other is QuantizedHit &&
      other.step == step &&
      other.snappedMs == snappedMs &&
      other.originalMs == originalMs &&
      other.strength == strength;

  @override
  int get hashCode => Object.hash(step, snappedMs, originalMs, strength);

  @override
  String toString() =>
      'QuantizedHit(step: $step, snappedMs: $snappedMs, from: $originalMs)';
}

/// The result of quantising: the subdivision actually used (≤ the skill cap) and
/// the snapped, de-duplicated hits in time (step) order.
class RhythmQuantization {
  /// Creates a quantisation result.
  const RhythmQuantization(this.resolution, this.hits);

  /// The subdivision the onsets were snapped to.
  final RhythmResolution resolution;

  /// The quantised notes, in step order, one per occupied grid step.
  final List<QuantizedHit> hits;

  /// Grid steps per beat at [resolution].
  int get stepsPerBeat => resolution.stepsPerBeat;
}

/// Snaps [ms] onto the grid of [resolution] (given [beatMs] ms per beat).
/// Returns the nearest `(stepIndex, snappedMs)`.
(int, double) snapToGrid(
  double ms,
  double beatMs,
  RhythmResolution resolution,
) {
  final stepMs = beatMs / resolution.stepsPerBeat;
  final step = (ms / stepMs).round();
  return (step, step * stepMs);
}

/// The worst grid deviation of [onsets] at [resolution], as a fraction of a
/// step (0 = dead on the grid, 0.5 = maximally between two grid lines).
double _worstDeviation(
  List<double> onsets,
  double beatMs,
  RhythmResolution r,
) {
  final stepMs = beatMs / r.stepsPerBeat;
  var worst = 0.0;
  for (final ms in onsets) {
    final frac = ms / stepMs;
    final dev = (frac - frac.roundToDouble()).abs();
    if (dev > worst) worst = dev;
  }
  return worst;
}

/// Whether two distinct onsets collapse onto the same step at [resolution]
/// (i.e. they'd be indistinguishable at that grid).
bool _hasCollision(List<double> onsets, double beatMs, RhythmResolution r) {
  final stepMs = beatMs / r.stepsPerBeat;
  final seen = <int>{};
  for (final ms in onsets) {
    if (!seen.add((ms / stepMs).round())) return true;
  }
  return false;
}

/// Auto-picks the coarsest subdivision that explains [onsets]: the first in the
/// ladder (quarter → eighth → triplet → sixteenth), never finer than [cap],
/// whose worst grid deviation is within [tolerance] (a fraction of a step) AND
/// where no two onsets collide. This is the "Relevanzschwelle": a beginner's
/// loose playing settles on the simplest grid that fits, and [cap] stops it ever
/// resolving finer than the player's skill tier. Falls back to [cap].
RhythmResolution chooseResolution(
  List<double> onsets, {
  required double beatMs,
  RhythmResolution cap = RhythmResolution.eighth,
  double tolerance = 0.2,
}) {
  if (beatMs <= 0 || onsets.length < 2) return RhythmResolution.quarter;
  for (final r in _ladder) {
    if (r.stepsPerBeat > cap.stepsPerBeat) break; // never exceed the skill cap
    if (_worstDeviation(onsets, beatMs, r) <= tolerance &&
        !_hasCollision(onsets, beatMs, r)) {
      return r;
    }
  }
  return cap;
}

/// Finds onsets in an energy [frames] trace: an rms jump over an absolute
/// [rmsFloor] AND a [riseFactor] rise vs the previous frame, with a
/// [refractoryMs] window so one hit isn't double-counted across adjacent
/// analysis frames. Strength = the peak rms across the attack. Generic over any
/// captured energy trace — the shared front to [quantizeRhythm]. Mirrors
/// `beat_capture`'s onset rule so a beatboxed and a tapped capture agree.
List<RhythmOnset> detectOnsets(
  List<EnergyFrame> frames, {
  double rmsFloor = 0.015,
  double riseFactor = 1.8,
  double refractoryMs = 90,
}) {
  final onsets = <RhythmOnset>[];
  var lastOnsetMs = -refractoryMs;
  var prevRms = 0.0;
  for (var i = 0; i < frames.length; i++) {
    final f = frames[i];
    final isOnset = f.rms > rmsFloor &&
        f.rms > prevRms * riseFactor &&
        f.ms - lastOnsetMs >= refractoryMs;
    prevRms = f.rms;
    if (!isOnset) continue;
    lastOnsetMs = f.ms;
    // Peak rms across the attack frames (within the refractory window).
    var peak = f.rms;
    for (var j = i + 1;
        j < frames.length && frames[j].ms - f.ms < refractoryMs;
        j++) {
      if (frames[j].rms > peak) peak = frames[j].rms;
    }
    onsets.add((ms: f.ms, strength: peak));
  }
  return onsets;
}

/// Quantise captured [onsets] to the grid the player can feel. Applies the
/// relevance threshold: onsets below [minStrength] are dropped as noise, the
/// subdivision is auto-chosen (≤ [cap], the skill tier), each onset snaps to
/// that grid, and hits landing on the same step collapse to one (the strongest
/// kept). Hits come back in step order. An empty/degenerate input yields an
/// empty quarter-grid result.
RhythmQuantization quantizeRhythm(
  List<RhythmOnset> onsets, {
  required double beatMs,
  RhythmResolution cap = RhythmResolution.eighth,
  double minStrength = 0.0,
  double tolerance = 0.2,
}) {
  final kept = [
    for (final o in onsets)
      if (o.strength >= minStrength) o,
  ]..sort((a, b) => a.ms.compareTo(b.ms));
  if (kept.isEmpty || beatMs <= 0) {
    return const RhythmQuantization(RhythmResolution.quarter, []);
  }
  final resolution = chooseResolution(
    [for (final o in kept) o.ms],
    beatMs: beatMs,
    cap: cap,
    tolerance: tolerance,
  );
  final stepMs = beatMs / resolution.stepsPerBeat;
  // Snap, then collapse same-step hits keeping the strongest.
  final byStep = <int, QuantizedHit>{};
  for (final o in kept) {
    final step = (o.ms / stepMs).round();
    final existing = byStep[step];
    if (existing == null || o.strength > existing.strength) {
      byStep[step] = QuantizedHit(
        step: step,
        snappedMs: step * stepMs,
        originalMs: o.ms,
        strength: o.strength,
      );
    }
  }
  final hits = byStep.values.toList()..sort((a, b) => a.step.compareTo(b.step));
  return RhythmQuantization(resolution, hits);
}
