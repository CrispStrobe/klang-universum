// Dynamics processors — compressor / limiter / gate. The app previously had no
// dynamics beyond the mixer's tanh soft-knee; these are proper level-dependent
// gain processors. Flutter-free, deterministic, same-length `Float64List →
// Float64List`. `mix == 0` is an exact identity copy.
//
// Design (feed-forward, log-domain gain computer + smoothed gain):
//   • Peak level → dB. A soft-knee gain computer maps over-threshold dB to a
//     gain-reduction in dB (ratio, knee). The linear reduction gain is smoothed
//     with an attack coefficient when it is DECREASING (clamping down) and a
//     release coefficient when recovering. Makeup is a constant post-gain.

import 'dart:math' as math;
import 'dart:typed_data';

double _log10(double x) => math.log(x) / math.ln10;

double _coef(double ms, double sampleRate) {
  final t = ms * 0.001 * sampleRate;
  return t <= 0 ? 0.0 : math.exp(-1 / t);
}

/// A soft-knee downward compressor. [thresholdDb] and [ratio] set where and how
/// hard it clamps; [attackMs]/[releaseMs] smooth the gain; [kneeDb] softens the
/// bend; [makeupDb] is constant post-gain.
Float64List compressorFx(
  Float64List input, {
  required double sampleRate,
  double thresholdDb = -18,
  double ratio = 4,
  double attackMs = 10,
  double releaseMs = 120,
  double kneeDb = 6,
  double makeupDb = 0,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final r = ratio < 1 ? 1.0 : ratio;
  final knee = kneeDb < 0 ? 0.0 : kneeDb;
  final atk = _coef(attackMs, sampleRate);
  final rel = _coef(releaseMs, sampleRate);
  final makeup = math.pow(10, makeupDb / 20).toDouble();
  final slope = 1 / r - 1; // dB out per dB over-threshold (negative)

  var gain = 1.0; // smoothed linear reduction gain
  for (var i = 0; i < input.length; i++) {
    final x = input[i];
    final levelDb = 20 * _log10(x.abs() + 1e-12);
    final over = levelDb - thresholdDb;
    double reductionDb;
    if (2 * over < -knee) {
      reductionDb = 0;
    } else if (knee > 0 && 2 * over <= knee) {
      final t = over + knee / 2;
      reductionDb = slope * t * t / (2 * knee); // quadratic knee
    } else {
      reductionDb = slope * over;
    }
    final target = math.pow(10, reductionDb / 20).toDouble();
    final c = target < gain ? atk : rel; // attack while clamping, release back
    gain = c * gain + (1 - c) * target;
    final wet = x * gain * makeup;
    out[i] = (1 - m) * x + m * wet;
  }
  return out;
}

/// A brick-wall-ish limiter — a high-ratio, fast, hard-knee compressor at a
/// ceiling ([ceilingDb]).
Float64List limiterFx(
  Float64List input, {
  required double sampleRate,
  double ceilingDb = -1,
  double releaseMs = 60,
  double mix = 1,
}) =>
    compressorFx(
      input,
      sampleRate: sampleRate,
      thresholdDb: ceilingDb,
      ratio: 20,
      attackMs: 1,
      releaseMs: releaseMs,
      kneeDb: 1,
      mix: mix,
    );

/// A noise gate / downward expander: signal at or above [thresholdDb] passes;
/// below it is attenuated toward [rangeDb] (the floor) at [ratio].
Float64List gateFx(
  Float64List input, {
  required double sampleRate,
  double thresholdDb = -40,
  double ratio = 4,
  double rangeDb = -60,
  double attackMs = 1,
  double releaseMs = 100,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final out = Float64List(input.length);
  if (m == 0) {
    out.setAll(0, input);
    return out;
  }
  final r = ratio < 1 ? 1.0 : ratio;
  final atk = _coef(attackMs, sampleRate);
  final rel = _coef(releaseMs, sampleRate);
  final floor = math.pow(10, rangeDb / 20).toDouble();

  var gain = 1.0;
  for (var i = 0; i < input.length; i++) {
    final x = input[i];
    final levelDb = 20 * _log10(x.abs() + 1e-12);
    double target;
    if (levelDb >= thresholdDb) {
      target = 1.0;
    } else {
      // Downward expander below the threshold.
      final reductionDb = (levelDb - thresholdDb) * (r - 1);
      target = math.max(floor, math.pow(10, reductionDb / 20).toDouble());
    }
    final c = target < gain ? rel : atk; // open fast, close on release
    gain = c * gain + (1 - c) * target;
    final wet = x * gain;
    out[i] = (1 - m) * x + m * wet;
  }
  return out;
}
