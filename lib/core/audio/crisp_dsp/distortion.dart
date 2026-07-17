// lib/core/audio/crisp_dsp/distortion.dart
//
// A waveshaping **distortion** set for the Tracker channel chain / SFX — the four
// classic shapes (hard clip, soft clip, fuzz, wavefold). Pure Dart, deterministic,
// a SAME-LENGTH transform (`Float64List → Float64List`). Flutter-free, tested like
// sample_dsp_test.dart. Drawn from crispaudio's chain (MIT). See docs/FX_HANDOVER.md #1.
//
// Contract:
//   • Per sample: `s = shape(input[i] * drive)`, then blend `out[i] =
//     (1-mix)*input[i] + mix*s`. `mix` in [0,1]; **mix == 0 MUST be an exact copy
//     of the input** (identity). Clamp mix to [0,1], drive to ≥ 0.
//   • Output length == input length; deterministic (no RNG/clock); finite; each
//     shaper's `s` is bounded to [-1, 1], so with a normalized dry input the
//     output stays within ~[-1, 1].
//   • Shapers (x = the driven sample):
//       hardClip : clamp(x, -1, 1)
//       softClip : tanh(x)                        (smooth saturation)
//       fuzz     : sign(x) * (1 - exp(-|x|))      (soft exponential grit → ±1)
//       waveFold : sin(x * pi / 2)                (smoothly folds back for |x|>1)

import 'dart:math' as math;
import 'dart:typed_data';

/// The waveshaper used by [distortionFx].
enum DistortionKind { hardClip, softClip, fuzz, waveFold }

/// Applies a waveshaping distortion to [input]. [drive] is the pre-gain into the
/// shaper (harder = more distortion); [mix] blends wet/dry.
Float64List distortionFx(
  Float64List input, {
  DistortionKind kind = DistortionKind.softClip,
  double drive = 4,
  double mix = 1,
}) {
  final m = mix.clamp(0.0, 1.0);
  final d = drive < 0 ? 0.0 : drive;
  final out = Float64List(input.length);

  // mix == 0 → exact element-wise copy of the input (identity).
  if (m == 0.0) {
    out.setAll(0, input);
    return out;
  }

  final dry = 1.0 - m;
  for (var i = 0; i < input.length; i++) {
    final x = input[i] * d;
    final s = _shape(kind, x);
    out[i] = dry * input[i] + m * s;
  }
  return out;
}

/// Waveshapes the driven sample [x] per [kind]. Output is bounded to [-1, 1].
double _shape(DistortionKind kind, double x) {
  switch (kind) {
    case DistortionKind.hardClip:
      return x.clamp(-1.0, 1.0);
    case DistortionKind.softClip:
      return _tanh(x);
    case DistortionKind.fuzz:
      final sign = x > 0
          ? 1.0
          : x < 0
              ? -1.0
              : 0.0;
      return sign * (1.0 - math.exp(-x.abs()));
    case DistortionKind.waveFold:
      return math.sin(x * math.pi / 2);
  }
}

/// Numerically-safe hyperbolic tangent (dart:math has no `tanh`).
double _tanh(double x) {
  if (x > 20.0) return 1.0;
  if (x < -20.0) return -1.0;
  final ep = math.exp(x);
  final en = math.exp(-x);
  return (ep - en) / (ep + en);
}
