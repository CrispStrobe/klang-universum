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

import 'package:comet_beat/core/audio/chroma_analysis.dart' show fft;

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

/// Closed-loop control of the NLMS learning rate — the filter picks its own step
/// per bin, per block, instead of running the hand-tuned [EchoCanceller.mu].
///
/// Implements Valin, "On Adjusting the Learning Rate in Frequency Domain Echo
/// Cancellation With Double-Talk" (IEEE TASLP 15(3), 2007; arXiv:1602.08044),
/// the control law Speex's MDF uses. Written from the paper, not from SpeexDSP —
/// this tree stays MIT (docs/AEC_TIER3B.md §licensing).
///
/// The idea: the optimal NLMS step is the ratio of residual-echo power to error
/// power (paper eq. 9, `mu_opt ≈ sigma_r^2 / sigma_e^2`). Both are unknown, but
/// the residual echo factors as `sigma_r^2(k) = eta * sigma_Yhat^2(k)` (eq. 15),
/// where **eta** is the echo *leakage* — the fraction of echo surviving into the
/// error — and `Yhat` is the filter's own echo estimate, which we have. So
/// (eq. 16):
///
///     mu_opt(k) = min( eta * |Yhat(k)|^2 / |E(k)|^2 , muMax )
///
/// eta is estimated by regressing the error's power spectrum on the echo
/// estimate's (eqs. 17–22), both DC-rejected to zero mean first so the
/// regression sees fluctuations rather than levels.
///
/// Why this subsumes hand-tuning AND the [DoubleTalkDetector]: when the near-end
/// speaks, |E|^2 jumps while |Yhat|^2 doesn't, so mu falls — the filter slows
/// down automatically, with no freeze decision and no threshold. When the echo
/// path changes, the leakage rises and mu climbs to re-converge. The paper's
/// framing: eta "is in fact the inverse of the echo return loss enhancement
/// (ERLE) of the filter", so the filter is steering by its own live ERLE.
class AdaptiveLearningRate {
  AdaptiveLearningRate({
    this.muMax = 0.5,
    this.initialMu = 0.25,
    this.initBlocks = 2,
    this.gamma = 0.1,
    this.beta0 = 0.05,
    this.eps = 1e-12,
  });

  /// Ceiling on the learning rate (paper: a design parameter ≤ 1, evaluated
  /// at 0.5).
  final double muMax;

  /// Fixed rate used while the filter is still converging and its echo estimate
  /// — and therefore the leakage regression — is meaningless (paper: 0.25).
  final double initialMu;

  /// How many blocks to hold [initialMu] for. The paper says twice the filter
  /// length; our filter is exactly one block long, so that is 2 blocks.
  final int initBlocks;

  /// DC-rejection constant for the power spectra (eqs. 17–18). The paper does
  /// not pin a value; this is ours, and a knob in [AecTuning].
  final double gamma;

  /// Base rate for the leakage regression's recursive averaging (eq. 22).
  /// Also unspecified by the paper; ours.
  final double beta0;

  final double eps;

  Float64List? _pY, _pE, _prevY, _prevE, _rEY, _rYY;
  int _block = 0;

  /// The current leakage estimate — the paper's eta, i.e. 1/ERLE. Near 0 = the
  /// filter is cancelling well; near 1 = the echo is passing straight through.
  /// Exposed because it is the single most diagnostic number in the loop.
  double leakage = 0;

  /// The rate this block ran at, averaged over bins — for tests and reports.
  double lastMeanMu = 0;

  /// Fills [muOut] with the per-bin learning rate for this block, given the
  /// power spectra of the echo estimate ([yPow]) and the error ([ePow]).
  void step(Float64List yPow, Float64List ePow, Float64List muOut) {
    final n = yPow.length;
    final pY = _pY ??= Float64List(n);
    final pE = _pE ??= Float64List(n);
    final prevY = _prevY ??= Float64List(n);
    final prevE = _prevE ??= Float64List(n);
    final rEY = _rEY ??= Float64List(n);
    final rYY = _rYY ??= Float64List(n);

    // Frame powers → the averaging weight (eq. 22). Slowing the regression when
    // the echo estimate is weak relative to the error is what stops silence and
    // double-talk from poisoning the leakage estimate.
    var sigY = 0.0, sigE = 0.0;
    for (var k = 0; k < n; k++) {
      sigY += yPow[k];
      sigE += ePow[k];
    }
    final beta = beta0 * (sigE <= eps ? 1.0 : (sigY / sigE).clamp(0.0, 1.0));

    // Zero-mean power spectra via first-order DC rejection (eqs. 17–18): the
    // regression must see how the spectra FLUCTUATE together, not their levels
    // (any two positive spectra correlate trivially on level alone).
    var sEY = 0.0, sYY = 0.0;
    for (var k = 0; k < n; k++) {
      pY[k] = (1 - gamma) * pY[k] + gamma * (yPow[k] - prevY[k]);
      pE[k] = (1 - gamma) * pE[k] + gamma * (ePow[k] - prevE[k]);
      rEY[k] = (1 - beta) * rEY[k] + beta * pY[k] * pE[k];
      rYY[k] = (1 - beta) * rYY[k] + beta * pY[k] * pY[k];
      sEY += rEY[k];
      sYY += rYY[k];
      prevY[k] = yPow[k];
      prevE[k] = ePow[k];
    }

    // eq. 19. Clamped to [0,1]: eta is a power ratio (1/ERLE), so a regression
    // that goes negative or above 1 is noise, not a filter that amplifies echo.
    leakage = (sYY <= eps ? 0.0 : sEY / sYY).clamp(0.0, 1.0);

    if (_block < initBlocks) {
      // The echo estimate is still garbage, so eta is too — run the paper's
      // fixed init rate rather than steering by a number we don't believe.
      muOut.fillRange(0, n, initialMu);
      lastMeanMu = initialMu;
    } else {
      var sum = 0.0;
      for (var k = 0; k < n; k++) {
        final m = (leakage * yPow[k] / (ePow[k] + eps)).clamp(0.0, muMax); // 16
        muOut[k] = m;
        sum += m;
      }
      lastMeanMu = sum / n;
    }
    _block += 1;
  }

  void reset() {
    _pY = _pE = _prevY = _prevE = _rEY = _rYY = null;
    _block = 0;
    leakage = 0;
    lastMeanMu = 0;
  }
}

class EchoCanceller {
  /// [blockSize] samples are processed at a time; the adaptive filter covers one
  /// block (~[blockSize]/sampleRate seconds of echo tail). [mu] is the NLMS step
  /// (0..2), [powerSmoothing] the per-bin power averaging factor.
  ///
  /// Pass [rate] to let the filter choose its own step instead of using [mu] —
  /// see [AdaptiveLearningRate]. Default null = the fixed-[mu] behaviour the C
  /// port mirrors, unchanged.
  EchoCanceller({
    this.blockSize = 1024,
    this.mu = 0.7,
    this.powerSmoothing = 0.9,
    this.eps = 1e-6,
    this.farEndFloor = 1e-5,
    this.regFactor = 1.0,
    this.leak = 1e-3,
    this.rate,
  })  : _n = 2 * blockSize,
        _wRe = Float64List(2 * blockSize),
        _wIm = Float64List(2 * blockSize),
        _xPrev = Float64List(blockSize),
        _power = Float64List(2 * blockSize);

  final int blockSize;
  final double mu;

  /// Per-bin reference-power smoothing (gentler adaptation → less near-end
  /// damage during double-talk).
  final double powerSmoothing;

  final double eps;

  /// Don't adapt the filter when the reference block's mean-square is below this
  /// — dividing by (near-)zero reference power is what makes NLMS diverge over
  /// the silent gaps in real audio. Filtering still happens; only learning
  /// pauses (a crude far-end voice-activity gate).
  final double farEndFloor;

  /// Denominator floor as a multiple of the block's mean spectral power. At
  /// ~1.0 it both bounds the step in spectral nulls AND stops the from-zero
  /// power estimate from blowing up on the first blocks of real audio.
  final double regFactor;

  /// Leakage: shrink the filter slightly each block so it can't drift to
  /// unbounded values under a loud, imperfectly-aligned reference (a standard
  /// robust-NLMS stabilizer).
  final double leak;

  /// When set, the step is chosen per bin per block by this controller and [mu]
  /// is ignored.
  final AdaptiveLearningRate? rate;

  final int _n; // FFT size = 2 * blockSize (overlap-save)
  final Float64List _wRe; // frequency-domain filter
  final Float64List _wIm;
  final Float64List _xPrev; // previous reference block (overlap)
  final Float64List _power; // smoothed per-bin reference power

  /// Cancel the echo of [reference] from [mic]. Both must be [blockSize] long
  /// and time-aligned (same block index). Returns the near-end estimate.
  ///
  /// [adapt] gates the NLMS filter update: pass false to FREEZE the filter for
  /// this block (still cancels with the current coefficients, but doesn't learn)
  /// — how a double-talk detector protects the filter from adapting on near-end
  /// speech. Overlap-save state advances either way. Default true = unchanged
  /// behaviour, so the C port and existing callers are untouched.
  Float64List process(
    Float64List reference,
    Float64List mic, {
    bool adapt = true,
  }) {
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

    // Far-end VAD: pause learning when the reference is (near) silent.
    var refMs = 0.0;
    for (var i = 0; i < b; i++) {
      refMs += reference[i] * reference[i];
    }
    if (!adapt || refMs / b < farEndFloor) {
      // Frozen (double-talk) or far-end silent: cancel with the current filter,
      // but don't learn. Advance the overlap-save state and return.
      for (var i = 0; i < b; i++) {
        _xPrev[i] = reference[i];
      }
      return out;
    }

    // E = FFT of [0 ; e]  (gradient uses the constrained error frame).
    final eRe = Float64List(n);
    final eIm = Float64List(n);
    for (var i = 0; i < b; i++) {
      eRe[b + i] = out[i];
    }
    fft(eRe, eIm);

    // A denominator floor tied to this block's mean spectral power: bounds the
    // step in spectral nulls and, crucially, stops the from-zero smoothed power
    // from producing an enormous step on the first blocks of real audio.
    var meanBinPow = 0.0;
    for (var k = 0; k < n; k++) {
      meanBinPow += xRe[k] * xRe[k] + xIm[k] * xIm[k];
    }
    final reg = regFactor * (meanBinPow / n) + eps;

    // The step: either the fixed [mu], or Valin's closed-loop rate, which needs
    // the error spectrum |E(k)|^2 we just computed.
    final controller = rate;
    Float64List? muPerBin;
    if (controller != null) {
      // Yhat must be measured in the SAME frame as E, which is the FFT of
      // [0 ; e] — so transform [0 ; yValid], not the raw W·X product. W·X spans
      // the whole 2b overlap-save frame, half of which is circular-wrap junk
      // that never reaches the output; comparing its spectrum against E's would
      // make eq. 16 a ratio of two different time windows.
      final yfRe = Float64List(n);
      final yfIm = Float64List(n);
      for (var i = 0; i < b; i++) {
        yfRe[b + i] = yRe[b + i]; // the valid (post-ifft) echo estimate
      }
      fft(yfRe, yfIm);
      final yPow = Float64List(n);
      final ePow = Float64List(n);
      for (var k = 0; k < n; k++) {
        yPow[k] = yfRe[k] * yfRe[k] + yfIm[k] * yfIm[k];
        ePow[k] = eRe[k] * eRe[k] + eIm[k] * eIm[k];
      }
      muPerBin = Float64List(n);
      controller.step(yPow, ePow, muPerBin);
    }

    // NLMS gradient  G = mu . conj(X) . E / (smoothedPower + reg), per bin.
    final gRe = Float64List(n);
    final gIm = Float64List(n);
    for (var k = 0; k < n; k++) {
      final p = xRe[k] * xRe[k] + xIm[k] * xIm[k];
      _power[k] = powerSmoothing * _power[k] + (1 - powerSmoothing) * p;
      final norm = (muPerBin?[k] ?? mu) / (_power[k] + reg);
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

    final keep = 1 - leak;
    for (var k = 0; k < n; k++) {
      _wRe[k] = keep * _wRe[k] + gRe[k];
      _wIm[k] = keep * _wIm[k] + gIm[k];
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
    rate?.reset();
  }
}
