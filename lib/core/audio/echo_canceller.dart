// lib/core/audio/echo_canceller.dart
//
// A compact acoustic echo canceller (AEC) — the linear core of what Speex MDF
// and WebRTC AEC3 do. Given the reference signal that was played out and the
// mic signal that (partly) captured it back, it estimates the speaker→mic path
// with a constrained frequency-domain block adaptive filter (overlap-save FDAF
// with NLMS) and subtracts the predicted echo, leaving the near-end (the user).
//
// Pure Dart, reusing the FFT from chroma_analysis.dart. Fully testable with a
// perfectly aligned digital mix (see test/echo_canceller_test.dart). The
// deployment challenge is NOT the algorithm but sample-accurate alignment of
// reference and mic across Flutter's separate audio plugins — that needs a
// native full-duplex path (see PLAN.md, Tier 3b). This class is what such a
// path would feed. It is a LINEAR canceller: it has no double-talk detector or
// nonlinear/residual-suppression stage yet, so production robustness still comes
// from SpeexDSP/WebRTC.

import 'dart:typed_data';

import 'package:klang_universum/core/audio/chroma_analysis.dart' show fft;

/// In-place inverse FFT built on the forward [fft] (conjugate → fft → conjugate
/// → scale).
void _ifft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 0; i < n; i++) {
    im[i] = -im[i];
  }
  fft(re, im);
  final inv = 1.0 / n;
  for (var i = 0; i < n; i++) {
    re[i] *= inv;
    im[i] = -im[i] * inv;
  }
}

class EchoCanceller {
  /// [blockSize] samples are processed at a time; the adaptive filter covers one
  /// block (~[blockSize]/sampleRate seconds of echo tail). [mu] is the NLMS step
  /// (0..2), [powerSmoothing] the per-bin power averaging factor.
  EchoCanceller({
    this.blockSize = 1024,
    this.mu = 0.7,
    this.powerSmoothing = 0.9,
    this.eps = 1e-6,
  })  : _n = 2 * blockSize,
        _wRe = Float64List(2 * blockSize),
        _wIm = Float64List(2 * blockSize),
        _xPrev = Float64List(blockSize),
        _power = Float64List(2 * blockSize);

  final int blockSize;
  final double mu;
  final double powerSmoothing;
  final double eps;

  final int _n; // FFT size = 2 * blockSize (overlap-save)
  final Float64List _wRe; // frequency-domain filter
  final Float64List _wIm;
  final Float64List _xPrev; // previous reference block (overlap)
  final Float64List _power; // per-bin reference power estimate

  /// Cancel the echo of [reference] from [mic]. Both must be [blockSize] long
  /// and time-aligned (same block index). Returns the near-end estimate.
  Float64List process(Float64List reference, Float64List mic) {
    assert(reference.length == blockSize && mic.length == blockSize);
    final b = blockSize;
    final n = _n;

    // X = FFT of [prevRef ; ref]  (overlap-save input frame).
    final xRe = Float64List(n);
    final xIm = Float64List(n);
    for (var i = 0; i < b; i++) {
      xRe[i] = _xPrev[i];
      xRe[b + i] = reference[i];
    }
    fft(xRe, xIm);

    // Y = W . X  (predicted echo, frequency domain) → time; keep the last block.
    final yRe = Float64List(n);
    final yIm = Float64List(n);
    for (var k = 0; k < n; k++) {
      yRe[k] = _wRe[k] * xRe[k] - _wIm[k] * xIm[k];
      yIm[k] = _wRe[k] * xIm[k] + _wIm[k] * xRe[k];
    }
    _ifft(yRe, yIm);

    // e = mic - echoEstimate (the valid overlap-save output = last block).
    final out = Float64List(b);
    for (var i = 0; i < b; i++) {
      out[i] = mic[i] - yRe[b + i];
    }

    // E = FFT of [0 ; e]  (gradient uses the constrained error frame).
    final eRe = Float64List(n);
    final eIm = Float64List(n);
    for (var i = 0; i < b; i++) {
      eRe[b + i] = out[i];
    }
    fft(eRe, eIm);

    // NLMS gradient  G = conj(X) . E / power, per bin.
    final gRe = Float64List(n);
    final gIm = Float64List(n);
    for (var k = 0; k < n; k++) {
      final p = xRe[k] * xRe[k] + xIm[k] * xIm[k];
      _power[k] = powerSmoothing * _power[k] + (1 - powerSmoothing) * p;
      final norm = mu / (_power[k] + eps);
      // conj(X) * E
      gRe[k] = (xRe[k] * eRe[k] + xIm[k] * eIm[k]) * norm;
      gIm[k] = (xRe[k] * eIm[k] - xIm[k] * eRe[k]) * norm;
    }

    // Gradient constraint: project the update onto a length-b time filter
    // (zero the second half) — this is what makes the FDAF a true linear
    // convolution rather than a circular one.
    _ifft(gRe, gIm);
    for (var i = b; i < n; i++) {
      gRe[i] = 0;
      gIm[i] = 0;
    }
    fft(gRe, gIm);

    for (var k = 0; k < n; k++) {
      _wRe[k] += gRe[k];
      _wIm[k] += gIm[k];
    }

    for (var i = 0; i < b; i++) {
      _xPrev[i] = reference[i];
    }
    return out;
  }

  void reset() {
    _wRe.fillRange(0, _n, 0);
    _wIm.fillRange(0, _n, 0);
    _xPrev.fillRange(0, blockSize, 0);
    _power.fillRange(0, _n, 0);
  }
}
