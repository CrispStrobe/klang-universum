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
