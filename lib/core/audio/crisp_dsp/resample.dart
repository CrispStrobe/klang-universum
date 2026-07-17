// lib/core/audio/crisp_dsp/resample.dart
//
// Linear-interpolation resampling — the per-note pitcher for sampled tracker
// instruments (classic MOD/tracker behaviour: playing a sample faster raises
// its pitch and shortens it). Also the grain resampler used by the granular
// pitch shifter. Pure Dart, Float64.

import 'dart:math';
import 'dart:typed_data';

/// Resamples [src] by [ratio] using linear interpolation. [ratio] is a playback
/// speed multiplier: `2.0` plays twice as fast (one octave up, half as long),
/// `0.5` half as fast (one octave down, twice as long). For a tracker note,
/// `ratio = targetFreq / baseFreq`. Returns a new buffer of length
/// `src.length / ratio`.
Float64List resampleLinear(Float64List src, double ratio) {
  if (ratio <= 0 || src.isEmpty) return Float64List(0);
  final outLen = (src.length / ratio).floor();
  final out = Float64List(outLen);
  for (var i = 0; i < outLen; i++) {
    final srcIndex = i * ratio;
    final f = srcIndex.floor();
    final c = min(f + 1, src.length - 1);
    final frac = srcIndex - f;
    out[i] = src[f] * (1 - frac) + src[c] * frac;
  }
  return out;
}

/// Resamples [src] by [ratio] using **4-point cubic (Catmull-Rom) interpolation**
/// — same semantics as [resampleLinear] (ratio = playback-speed multiplier,
/// output length `src.length / ratio`) but smoother: the C1-continuous cubic fits
/// the two samples on each side, so a pitched sample has far less interpolation
/// hiss than the piecewise-linear version. This is the pitcher for sampled
/// instruments (a borrowed module sample, the recorded voice). Endpoints clamp
/// the neighbour taps to the sample bounds.
Float64List resampleCubic(Float64List src, double ratio) {
  if (ratio <= 0 || src.isEmpty) return Float64List(0);
  final n = src.length;
  if (n == 1) return Float64List.fromList([src[0]]);
  final outLen = (n / ratio).floor();
  final out = Float64List(outLen);
  for (var i = 0; i < outLen; i++) {
    final srcIndex = i * ratio;
    final f = srcIndex.floor();
    final t = srcIndex - f;
    final p0 = src[max(f - 1, 0)];
    final p1 = src[f];
    final p2 = src[min(f + 1, n - 1)];
    final p3 = src[min(f + 2, n - 1)];
    // Catmull-Rom: 0.5·(2p1 + (-p0+p2)t + (2p0-5p1+4p2-p3)t² + (-p0+3p1-3p2+p3)t³)
    final t2 = t * t;
    final t3 = t2 * t;
    out[i] = 0.5 *
        (2 * p1 +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
  }
  return out;
}
