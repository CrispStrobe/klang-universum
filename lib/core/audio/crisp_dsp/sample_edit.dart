// lib/core/audio/crisp_dsp/sample_edit.dart
//
// Non-destructive PCM editing primitives for the Tracker's sampled instruments
// (recorded voice, borrowed module samples): trim, silence-strip, normalize,
// fade in/out, reverse. Each takes a normalized ±1 [Float64List] and returns a
// NEW buffer — the input is never mutated, so an editor can preview an op and
// discard it. Pure Dart, deterministic. Ideas from voicelab + crispaudio's
// timeline editor (TRACKER_IDEAS §B).

import 'dart:typed_data';

/// The peak magnitude (max |sample|) of [pcm]; 0 for an empty or silent buffer.
double peakMagnitude(Float64List pcm) {
  var m = 0.0;
  for (final v in pcm) {
    final a = v.abs();
    if (a > m) m = a;
  }
  return m;
}

/// [pcm] with samples outside `[start, end)` removed (a new buffer). [end]
/// defaults to the end. Indices are clamped and ordered, so out-of-range or
/// reversed args can't throw — they just yield an empty or full slice.
Float64List trimPcm(Float64List pcm, int start, [int? end]) {
  final n = pcm.length;
  var a = start.clamp(0, n);
  var b = (end ?? n).clamp(0, n);
  if (b < a) {
    final t = a;
    a = b;
    b = t;
  }
  return pcm.sublist(a, b);
}

/// [pcm] with leading and trailing samples quieter than [threshold] (a fraction
/// of full scale, default 0.01) removed — the usual "strip the silence around a
/// recording". An all-silent buffer yields an empty one.
Float64List trimSilence(Float64List pcm, {double threshold = 0.01}) {
  final n = pcm.length;
  var lo = 0;
  while (lo < n && pcm[lo].abs() < threshold) {
    lo++;
  }
  if (lo == n) return Float64List(0);
  var hi = n;
  while (hi > lo && pcm[hi - 1].abs() < threshold) {
    hi--;
  }
  return pcm.sublist(lo, hi);
}

/// [pcm] scaled so its peak magnitude equals [targetPeak] (default 1.0 = full
/// scale) — a new buffer. A silent buffer is returned unchanged (nothing to
/// scale). [targetPeak] is not clamped, so >1 is allowed (and may clip on play).
Float64List normalizePcm(Float64List pcm, {double targetPeak = 1.0}) {
  final peak = peakMagnitude(pcm);
  if (peak == 0) return Float64List.fromList(pcm);
  final g = targetPeak / peak;
  final out = Float64List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = pcm[i] * g;
  }
  return out;
}

/// A copy of [pcm] with a linear fade-in over the first [samples] (clamped to
/// the length). The first sample is silent, ramping to full by the fade's end;
/// 0 → an identity copy.
Float64List fadeIn(Float64List pcm, int samples) {
  final out = Float64List.fromList(pcm);
  final f = samples.clamp(0, out.length);
  for (var i = 0; i < f; i++) {
    out[i] *= i / f;
  }
  return out;
}

/// A copy of [pcm] with a linear fade-out over the last [samples] (clamped). The
/// last sample is silent, ramping up as you move back into the buffer; mirrors
/// [fadeIn].
Float64List fadeOut(Float64List pcm, int samples) {
  final out = Float64List.fromList(pcm);
  final n = out.length;
  final f = samples.clamp(0, n);
  for (var i = 0; i < f; i++) {
    out[n - 1 - i] *= i / f;
  }
  return out;
}

/// [pcm] reversed (a new buffer) — a playful "backwards sample" edit.
Float64List reversePcm(Float64List pcm) {
  final n = pcm.length;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = pcm[n - 1 - i];
  }
  return out;
}
