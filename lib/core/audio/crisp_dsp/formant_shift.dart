// lib/core/audio/crisp_dsp/formant_shift.dart
//
// Formant shifter: warps the spectral ENVELOPE while leaving the harmonics — and
// therefore the pitch — exactly where they are.
//
// Formant shifting changes vocal-tract character (bright "small head" ↔ dark
// "big head") WITHOUT changing pitch or length — that is what makes a recorded
// voice usable as an in-tune tracker instrument, where the grid note (via the
// instrument's baseMidi) is what decides the pitch.
//
// History / why this is an STFT method: the previous port scaled *time-domain*
// indices of each Hann frame. Scaling time indices RESAMPLES the frame, which is
// a pitch shift — it drags the pitch and the formants together. Measured through
// the app's own detector, a recorded C4 came back at +493 cents (chipmunk),
// −693 (monster) and −1908 (deep), so the voice channel played badly out of tune
// against every other channel — the exact failure the pitch-preserving contract
// in voice_fx.dart exists to prevent. Time-domain resampling CANNOT decouple the
// envelope from the pitch (both scale together), so a real spectral method is
// required:
//   1. Hann-windowed frames at 75% overlap → FFT.
//   2. Cepstral liftering yields the smooth spectral envelope: the low-quefrency
//      part of the real cepstrum of the log-magnitude spectrum. The pitch lives
//      at quefrency ≈ the period, well above [quefrencyCutoff], so it is
//      excluded from the envelope by construction.
//   3. Warp that envelope along frequency by the ratio and apply the difference
//      as a per-bin real GAIN — magnitude only, phase untouched — so every
//      harmonic stays in its original bin and the pitch is preserved.
//   4. Inverse FFT, synthesis window, overlap-add, normalized by the summed
//      window² (proper COLA, so the edges are not amplitude-ramped).

import 'dart:math';
import 'dart:typed_data';

// The app's radix-2 FFT lives here; no need for a second copy in crisp_dsp.
import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;

Float64List _hannWindow(int size) {
  final w = Float64List(size);
  for (var i = 0; i < size; i++) {
    w[i] = 0.5 * (1 - cos((2 * pi * i) / (size - 1)));
  }
  return w;
}

/// In-place inverse FFT, via the conjugate trick: `ifft(x) = conj(fft(conj(x)))/n`.
void _ifft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 0; i < n; i++) {
    im[i] = -im[i];
  }
  fft(re, im);
  for (var i = 0; i < n; i++) {
    re[i] /= n;
    im[i] = -im[i] / n;
  }
}

/// Linear interpolation of [v] at fractional index [x], clamped to 0..[maxIdx].
double _lerpAt(Float64List v, double x, int maxIdx) {
  if (x <= 0) return v[0];
  if (x >= maxIdx) return v[maxIdx];
  final i = x.floor();
  final f = x - i;
  return v[i] * (1 - f) + v[i + 1] * f;
}

/// Shifts the formants of [input] by [shift] (−1..+1; 0 = no change). Positive
/// shifts formants up (brighter/smaller), negative down (darker/bigger). Pitch
/// and length are preserved.
///
/// [fftSize] is the analysis frame size (shrunk automatically for short clips).
/// [quefrencyCutoff] sets how smooth the extracted envelope is; it must stay
/// below the pitch period in samples so the envelope excludes the harmonics
/// (32 ≈ everything below a 1.4 kHz fundamental at 44.1 kHz).
Float64List formantShift(
  Float64List input,
  double shift, {
  int fftSize = 2048,
  int quefrencyCutoff = 32,
}) {
  if (shift == 0 || input.isEmpty) return input;
  final n = input.length;

  // Shrink the frame to fit short clips. The old implementation derived
  // frameCount = length ~/ hop, so anything under one hop (512 samples) skipped
  // the loop entirely and returned a freshly-allocated buffer — i.e. pure
  // SILENCE, with no error. Returning the input untouched is the honest floor.
  var size = fftSize;
  while (size > 128 && size > n) {
    size >>= 1;
  }
  if (n < size) return input;

  final hop = size ~/ 4;
  final window = _hannWindow(size);
  final ratio = pow(2, shift).toDouble(); // −1 → 0.5, +1 → 2.0
  final half = size ~/ 2;

  final out = Float64List(n);
  final norm = Float64List(n); // summed window², for exact COLA normalization

  final re = Float64List(size);
  final im = Float64List(size);
  final cre = Float64List(size);
  final cim = Float64List(size);
  final gain = Float64List(size);

  // Start before 0 so the first samples get full window coverage too.
  for (var pos = -(size - hop); pos < n; pos += hop) {
    // 1. Windowed frame (zero outside the signal).
    for (var i = 0; i < size; i++) {
      final idx = pos + i;
      re[i] = (idx >= 0 && idx < n) ? input[idx] * window[i] : 0.0;
      im[i] = 0.0;
    }
    fft(re, im);

    // 2. Smooth spectral envelope (log domain) via cepstral liftering.
    for (var k = 0; k < size; k++) {
      cre[k] = log(sqrt(re[k] * re[k] + im[k] * im[k]) + 1e-10);
      cim[k] = 0.0;
    }
    _ifft(cre, cim); // real cepstrum
    for (var q = quefrencyCutoff; q <= size - quefrencyCutoff; q++) {
      cre[q] = 0;
      cim[q] = 0;
    }
    fft(cre, cim); // → the log envelope, in cre

    // 3. Warp the envelope and apply the delta as a magnitude-only gain. Phase
    //    is untouched, so harmonics stay put → pitch is preserved.
    for (var k = 0; k <= half; k++) {
      final warped = _lerpAt(cre, k / ratio, half);
      final g = exp(warped - cre[k]).clamp(0.03, 32.0);
      gain[k] = g;
      if (k > 0 && k < half) gain[size - k] = g; // conjugate symmetry
    }
    for (var k = 0; k < size; k++) {
      re[k] *= gain[k];
      im[k] *= gain[k];
    }

    // 4. Back to the time domain; synthesis window + overlap-add.
    _ifft(re, im);
    for (var i = 0; i < size; i++) {
      final idx = pos + i;
      if (idx >= 0 && idx < n) {
        out[idx] += re[i] * window[i];
        norm[idx] += window[i] * window[i];
      }
    }
  }

  for (var i = 0; i < n; i++) {
    if (norm[i] > 1e-6) out[i] /= norm[i];
  }

  // Shifting the envelope up boosts bins the source barely occupied, so the
  // result can overshoot the input badly (a 0.7-peak voice came back at 2.12 —
  // hard clipping once it reaches PCM16). Cap at the input's peak: attenuate
  // only, never invent gain, so a quiet clip stays quiet and the sample keeps a
  // predictable instrument level.
  var inPeak = 0.0, outPeak = 0.0;
  for (var i = 0; i < n; i++) {
    final a = input[i].abs();
    if (a > inPeak) inPeak = a;
    final b = out[i].abs();
    if (b > outPeak) outPeak = b;
  }
  if (outPeak > inPeak && inPeak > 0) {
    final g = inPeak / outPeak;
    for (var i = 0; i < n; i++) {
      out[i] *= g;
    }
  }
  return out;
}
