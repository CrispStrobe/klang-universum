// aec_dsp.c — cleanroom C port of echo_canceller.dart + chroma_analysis.dart's
// FFT. See aec_dsp.h. MIT (ours). Kept structurally identical to the Dart so the
// offline ERLE test is a true cross-check.

#include "aec_dsp.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

struct AecDsp {
  int blockSize;  // b
  int n;          // FFT size = 2*b (overlap-save)
  double mu;
  double powerSmoothing;
  double eps;
  double farEndFloor;
  double regFactor;
  double leak;
  int adapt;  // 1 = learn (default); 0 = freeze the filter this block (DTD)

  // Persistent state (mirrors the Dart fields).
  double* wRe;    // n — frequency-domain filter
  double* wIm;    // n
  double* xPrev;  // b — previous reference block (overlap)
  double* power;  // n — smoothed per-bin reference power

  // Preallocated per-block scratch (Dart allocates these each call; we reuse).
  double* xRe;  // n
  double* xIm;  // n
  double* yRe;  // n
  double* yIm;  // n
  double* eRe;  // n
  double* eIm;  // n
  double* gRe;  // n
  double* gIm;  // n

  // Adaptive learning rate (optional; NULL = fixed-mu path, byte-identical to
  // the pre-existing behaviour the ERLE cross-check pins). Owned by the caller.
  struct AecRate* rate;
  double* yfRe;      // n — Yhat measured in the constrained [0;yValid] frame
  double* yfIm;      // n
  double* yPow;      // n — |Yhat(k)|^2
  double* ePow;      // n — |E(k)|^2
  double* muPerBin;  // n — the per-bin step the controller chose
};

// In-place iterative radix-2 Cooley-Tukey FFT — port of chroma_analysis.dart.
void aec_fft(double* re, double* im, int n) {
  if (n <= 1) return;

  // Bit-reversal permutation.
  for (int i = 1, j = 0; i < n; i++) {
    int bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      double tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      double ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  // Danielson-Lanczos butterflies.
  for (int len = 2; len <= n; len <<= 1) {
    double ang = -2.0 * M_PI / len;
    double wLenRe = cos(ang);
    double wLenIm = sin(ang);
    for (int i = 0; i < n; i += len) {
      double wRe = 1.0;
      double wIm = 0.0;
      int half = len >> 1;
      for (int k = 0; k < half; k++) {
        double uRe = re[i + k];
        double uIm = im[i + k];
        double vRe = re[i + k + half] * wRe - im[i + k + half] * wIm;
        double vIm = re[i + k + half] * wIm + im[i + k + half] * wRe;
        re[i + k] = uRe + vRe;
        im[i + k] = uIm + vIm;
        re[i + k + half] = uRe - vRe;
        im[i + k + half] = uIm - vIm;
        double nWRe = wRe * wLenRe - wIm * wLenIm;
        wIm = wRe * wLenIm + wIm * wLenRe;
        wRe = nWRe;
      }
    }
  }
}

// In-place inverse FFT built on the forward transform (conj -> fft -> conj ->
// scale) — port of echo_canceller.dart's _ifft.
static void ifft(double* re, double* im, int n) {
  for (int i = 0; i < n; i++) im[i] = -im[i];
  aec_fft(re, im, n);
  double inv = 1.0 / n;
  for (int i = 0; i < n; i++) {
    re[i] *= inv;
    im[i] = -im[i] * inv;
  }
}

static int is_pow2(int n) { return n > 0 && (n & (n - 1)) == 0; }

AecDsp* aec_dsp_create(int blockSize, double mu, double powerSmoothing,
                       double eps, double farEndFloor, double regFactor,
                       double leak) {
  if (!is_pow2(blockSize)) return NULL;
  AecDsp* a = (AecDsp*)calloc(1, sizeof(AecDsp));
  if (!a) return NULL;
  a->blockSize = blockSize;
  a->n = 2 * blockSize;
  a->mu = mu;
  a->powerSmoothing = powerSmoothing;
  a->eps = eps;
  a->farEndFloor = farEndFloor;
  a->regFactor = regFactor;
  a->leak = leak;
  a->adapt = 1;

  int n = a->n, b = a->blockSize;
  // One calloc'd pool would be nicer, but keep it obvious: individual buffers.
  a->wRe = (double*)calloc(n, sizeof(double));
  a->wIm = (double*)calloc(n, sizeof(double));
  a->xPrev = (double*)calloc(b, sizeof(double));
  a->power = (double*)calloc(n, sizeof(double));
  a->xRe = (double*)calloc(n, sizeof(double));
  a->xIm = (double*)calloc(n, sizeof(double));
  a->yRe = (double*)calloc(n, sizeof(double));
  a->yIm = (double*)calloc(n, sizeof(double));
  a->eRe = (double*)calloc(n, sizeof(double));
  a->eIm = (double*)calloc(n, sizeof(double));
  a->gRe = (double*)calloc(n, sizeof(double));
  a->gIm = (double*)calloc(n, sizeof(double));

  a->rate = NULL;  // fixed-mu path until a controller is attached
  a->yfRe = (double*)calloc(n, sizeof(double));
  a->yfIm = (double*)calloc(n, sizeof(double));
  a->yPow = (double*)calloc(n, sizeof(double));
  a->ePow = (double*)calloc(n, sizeof(double));
  a->muPerBin = (double*)calloc(n, sizeof(double));

  if (!a->wRe || !a->wIm || !a->xPrev || !a->power || !a->xRe || !a->xIm ||
      !a->yRe || !a->yIm || !a->eRe || !a->eIm || !a->gRe || !a->gIm ||
      !a->yfRe || !a->yfIm || !a->yPow || !a->ePow || !a->muPerBin) {
    aec_dsp_destroy(a);
    return NULL;
  }
  return a;
}

AecDsp* aec_dsp_create_default(int blockSize) {
  return aec_dsp_create(blockSize, 0.7, 0.9, 1e-6, 1e-5, 1.0, 1e-3);
}

int aec_dsp_block_size(const AecDsp* a) { return a ? a->blockSize : 0; }

void aec_dsp_reset(AecDsp* a) {
  if (!a) return;
  int n = a->n, b = a->blockSize;
  memset(a->wRe, 0, n * sizeof(double));
  memset(a->wIm, 0, n * sizeof(double));
  memset(a->xPrev, 0, b * sizeof(double));
  memset(a->power, 0, n * sizeof(double));
}

// Fills muOut[0..n) with the per-bin learning rate for this block, given the
// power spectra of the echo estimate (yPow) and the error (ePow). Defined with
// the rest of the AecRate implementation below.
static void aec_rate_step(AecRate* r, const double* yPow, const double* ePow,
                          int n, double* muOut);

void aec_dsp_process(AecDsp* a, const double* reference, const double* mic,
                     double* out) {
  const int b = a->blockSize;
  const int n = a->n;

  double* xRe = a->xRe;
  double* xIm = a->xIm;
  double* yRe = a->yRe;
  double* yIm = a->yIm;
  double* eRe = a->eRe;
  double* eIm = a->eIm;
  double* gRe = a->gRe;
  double* gIm = a->gIm;

  // X = FFT of [prevRef ; ref] (overlap-save input frame).
  memset(xIm, 0, n * sizeof(double));
  for (int i = 0; i < b; i++) {
    xRe[i] = a->xPrev[i];
    xRe[b + i] = reference[i];
  }
  aec_fft(xRe, xIm, n);

  // Y = W . X (predicted echo, freq domain) -> time; keep the last block.
  for (int k = 0; k < n; k++) {
    yRe[k] = a->wRe[k] * xRe[k] - a->wIm[k] * xIm[k];
    yIm[k] = a->wRe[k] * xIm[k] + a->wIm[k] * xRe[k];
  }
  ifft(yRe, yIm, n);

  // e = mic - echoEstimate (valid overlap-save output = last block).
  for (int i = 0; i < b; i++) {
    out[i] = mic[i] - yRe[b + i];
  }

  // Frozen (double-talk detector) or far-end silent: cancel with the current
  // filter, but don't learn. Advance the overlap-save state and return.
  double refMs = 0.0;
  for (int i = 0; i < b; i++) refMs += reference[i] * reference[i];
  if (!a->adapt || refMs / b < a->farEndFloor) {
    for (int i = 0; i < b; i++) a->xPrev[i] = reference[i];
    return;
  }

  // E = FFT of [0 ; e] (constrained error frame).
  memset(eRe, 0, n * sizeof(double));
  memset(eIm, 0, n * sizeof(double));
  for (int i = 0; i < b; i++) eRe[b + i] = out[i];
  aec_fft(eRe, eIm, n);

  // Denominator floor tied to this block's mean spectral power.
  double meanBinPow = 0.0;
  for (int k = 0; k < n; k++) meanBinPow += xRe[k] * xRe[k] + xIm[k] * xIm[k];
  double reg = a->regFactor * (meanBinPow / n) + a->eps;

  // The step: either the fixed mu, or the closed-loop rate. Yhat must be
  // measured in the SAME frame as E (the FFT of [0 ; e]) — so transform
  // [0 ; yValid], not the raw W·X product (a different time window). See the
  // Dart AdaptiveLearningRate.
  const double* muPerBin = NULL;
  if (a->rate) {
    memset(a->yfRe, 0, n * sizeof(double));
    memset(a->yfIm, 0, n * sizeof(double));
    for (int i = 0; i < b; i++) a->yfRe[b + i] = yRe[b + i];
    aec_fft(a->yfRe, a->yfIm, n);
    for (int k = 0; k < n; k++) {
      a->yPow[k] = a->yfRe[k] * a->yfRe[k] + a->yfIm[k] * a->yfIm[k];
      a->ePow[k] = eRe[k] * eRe[k] + eIm[k] * eIm[k];
    }
    aec_rate_step(a->rate, a->yPow, a->ePow, n, a->muPerBin);
    muPerBin = a->muPerBin;
  }

  // NLMS gradient G = mu . conj(X) . E / (smoothedPower + reg), per bin.
  for (int k = 0; k < n; k++) {
    double p = xRe[k] * xRe[k] + xIm[k] * xIm[k];
    a->power[k] = a->powerSmoothing * a->power[k] + (1 - a->powerSmoothing) * p;
    double norm = (muPerBin ? muPerBin[k] : a->mu) / (a->power[k] + reg);
    gRe[k] = (xRe[k] * eRe[k] + xIm[k] * eIm[k]) * norm;   // conj(X)*E real
    gIm[k] = (xRe[k] * eIm[k] - xIm[k] * eRe[k]) * norm;   // conj(X)*E imag
  }

  // Gradient constraint: project onto a length-b time filter (zero 2nd half) so
  // the FDAF performs a true linear convolution, not a circular one.
  ifft(gRe, gIm, n);
  for (int i = b; i < n; i++) {
    gRe[i] = 0;
    gIm[i] = 0;
  }
  aec_fft(gRe, gIm, n);

  double keep = 1.0 - a->leak;
  for (int k = 0; k < n; k++) {
    a->wRe[k] = keep * a->wRe[k] + gRe[k];
    a->wIm[k] = keep * a->wIm[k] + gIm[k];
  }

  for (int i = 0; i < b; i++) a->xPrev[i] = reference[i];
}

void aec_dsp_destroy(AecDsp* a) {
  if (!a) return;
  free(a->wRe);
  free(a->wIm);
  free(a->xPrev);
  free(a->power);
  free(a->xRe);
  free(a->xIm);
  free(a->yRe);
  free(a->yIm);
  free(a->eRe);
  free(a->eIm);
  free(a->gRe);
  free(a->gIm);
  free(a->yfRe);
  free(a->yfIm);
  free(a->yPow);
  free(a->ePow);
  free(a->muPerBin);
  free(a);
}

void aec_dsp_set_adapt(AecDsp* a, int adapt) {
  if (a) a->adapt = adapt ? 1 : 0;
}

void aec_dsp_set_rate(AecDsp* a, AecRate* rate) {
  if (a) a->rate = rate;
}

// --- Adaptive learning rate (port of echo_canceller.dart's AdaptiveLearningRate)
//
// Valin, IEEE TASLP 2007. The optimal NLMS step is the ratio of residual-echo to
// error power; the residual factors as eta*|Yhat|^2 where eta is the echo
// leakage (=1/ERLE), estimated by regressing the error's power spectrum on the
// echo estimate's (both DC-rejected to zero mean). Per bin, per block:
//   mu_opt(k) = min( eta * |Yhat(k)|^2 / |E(k)|^2 , muMax )
// When the near-end speaks |E| jumps but |Yhat| doesn't, so mu falls and the
// filter slows itself — subsuming double-talk detection with no freeze decision.

struct AecRate {
  double muMax;
  double initialMu;
  int initBlocks;
  double gamma;
  double beta0;
  double eps;
  int block;
  double leakage;     // eta = 1/ERLE
  double lastMeanMu;  // mean step chosen on the last block (diagnostic)
  int n;              // 0 until the first step learns the FFT size
  double* pY;         // n — zero-mean echo-estimate power spectrum
  double* pE;         // n — zero-mean error power spectrum
  double* prevY;      // n
  double* prevE;      // n
  double* rEY;        // n — cross-power regression accumulator
  double* rYY;        // n — auto-power regression accumulator
};

AecRate* aec_rate_create(double muMax, double initialMu, int initBlocks,
                         double gamma, double beta0, double eps) {
  AecRate* r = (AecRate*)calloc(1, sizeof(AecRate));
  if (!r) return NULL;
  r->muMax = muMax;
  r->initialMu = initialMu;
  r->initBlocks = initBlocks;
  r->gamma = gamma;
  r->beta0 = beta0;
  r->eps = eps;
  r->n = 0;  // state arrays allocated lazily on the first step
  return r;
}

AecRate* aec_rate_create_default(void) {
  return aec_rate_create(0.5, 0.25, 2, 0.1, 0.05, 1e-12);
}

double aec_rate_leakage(const AecRate* r) { return r ? r->leakage : 0.0; }
double aec_rate_last_mean_mu(const AecRate* r) {
  return r ? r->lastMeanMu : 0.0;
}

static void aec_rate_free_state(AecRate* r) {
  free(r->pY);
  free(r->pE);
  free(r->prevY);
  free(r->prevE);
  free(r->rEY);
  free(r->rYY);
  r->pY = r->pE = r->prevY = r->prevE = r->rEY = r->rYY = NULL;
  r->n = 0;
}

void aec_rate_reset(AecRate* r) {
  if (!r) return;
  aec_rate_free_state(r);  // reallocated (zeroed) on the next step
  r->block = 0;
  r->leakage = 0.0;
  r->lastMeanMu = 0.0;
}

void aec_rate_destroy(AecRate* r) {
  if (!r) return;
  aec_rate_free_state(r);
  free(r);
}

static void aec_rate_step(AecRate* r, const double* yPow, const double* ePow,
                          int n, double* muOut) {
  if (r->n != n) {
    // First step (or a size change): (re)allocate zeroed state for this n.
    aec_rate_free_state(r);
    r->pY = (double*)calloc((size_t)n, sizeof(double));
    r->pE = (double*)calloc((size_t)n, sizeof(double));
    r->prevY = (double*)calloc((size_t)n, sizeof(double));
    r->prevE = (double*)calloc((size_t)n, sizeof(double));
    r->rEY = (double*)calloc((size_t)n, sizeof(double));
    r->rYY = (double*)calloc((size_t)n, sizeof(double));
    r->n = n;
  }

  // Frame powers -> the averaging weight (eq. 22). Slowing the regression when
  // the echo estimate is weak vs the error keeps silence and double-talk from
  // poisoning the leakage estimate.
  double sigY = 0.0, sigE = 0.0;
  for (int k = 0; k < n; k++) {
    sigY += yPow[k];
    sigE += ePow[k];
  }
  double ratio = sigE <= r->eps ? 1.0 : sigY / sigE;
  if (ratio < 0.0) ratio = 0.0;
  if (ratio > 1.0) ratio = 1.0;
  double beta = r->beta0 * ratio;

  // Zero-mean power spectra via first-order DC rejection (eqs. 17-18), then the
  // recursive regression accumulators (eqs. 20-21).
  double sEY = 0.0, sYY = 0.0;
  for (int k = 0; k < n; k++) {
    r->pY[k] = (1 - r->gamma) * r->pY[k] + r->gamma * (yPow[k] - r->prevY[k]);
    r->pE[k] = (1 - r->gamma) * r->pE[k] + r->gamma * (ePow[k] - r->prevE[k]);
    r->rEY[k] = (1 - beta) * r->rEY[k] + beta * r->pY[k] * r->pE[k];
    r->rYY[k] = (1 - beta) * r->rYY[k] + beta * r->pY[k] * r->pY[k];
    sEY += r->rEY[k];
    sYY += r->rYY[k];
    r->prevY[k] = yPow[k];
    r->prevE[k] = ePow[k];
  }

  // eq. 19, clamped to [0,1] (eta is a power ratio = 1/ERLE).
  double eta = sYY <= r->eps ? 0.0 : sEY / sYY;
  if (eta < 0.0) eta = 0.0;
  if (eta > 1.0) eta = 1.0;
  r->leakage = eta;

  if (r->block < r->initBlocks) {
    // The echo estimate is still garbage, so eta is too — run the fixed init
    // rate rather than steering by a number we don't yet believe.
    for (int k = 0; k < n; k++) muOut[k] = r->initialMu;
    r->lastMeanMu = r->initialMu;
  } else {
    double sum = 0.0;
    for (int k = 0; k < n; k++) {
      double m = eta * yPow[k] / (ePow[k] + r->eps);  // eq. 16
      if (m < 0.0) m = 0.0;
      if (m > r->muMax) m = r->muMax;
      muOut[k] = m;
      sum += m;
    }
    r->lastMeanMu = sum / n;
  }
  r->block += 1;
}

// --- Double-talk detector (port of aec_offline.dart's DoubleTalkDetector) ----
//
// Statistic: normalized correlation between the mic and the filter's echo
// estimate (echoEst = mic - cleaned = W·x). Far-end single-talk -> the estimate
// tracks the mic -> correlation ~1; double-talk -> the near-end enters the mic
// but not the estimate -> correlation drops. A warmup guard lets the filter
// converge first; a hangover holds the freeze through brief dips.

struct AecDtd {
  double threshold;
  int hangoverBlocks;
  int warmupBlocks;
  double farEndFloor;
  int block;
  int hangover;
};

AecDtd* aec_dtd_create(double threshold, int hangoverBlocks, int warmupBlocks,
                       double farEndFloor) {
  AecDtd* d = (AecDtd*)calloc(1, sizeof(AecDtd));
  if (!d) return NULL;
  d->threshold = threshold;
  d->hangoverBlocks = hangoverBlocks;
  d->warmupBlocks = warmupBlocks;
  d->farEndFloor = farEndFloor;
  d->block = 0;
  d->hangover = 0;
  return d;
}

AecDtd* aec_dtd_create_default(void) {
  // Mirrors the Dart DoubleTalkDetector defaults.
  return aec_dtd_create(0.9, 8, 12, 1e-5);
}

// True (1) if the NEXT block should freeze adaptation. Read before processing,
// then call aec_dtd_update() after.
int aec_dtd_freeze(const AecDtd* d) { return (d && d->hangover > 0) ? 1 : 0; }

void aec_dtd_update(AecDtd* d, const double* reference, const double* mic,
                    const double* cleaned, int blockSize) {
  if (!d) return;
  d->block += 1;
  double refMs = 0.0;
  for (int i = 0; i < blockSize; i++) refMs += reference[i] * reference[i];
  if (refMs / blockSize >= d->farEndFloor && d->block > d->warmupBlocks) {
    double dot = 0.0, mm = 0.0, ee = 0.0;
    for (int i = 0; i < blockSize; i++) {
      double e = mic[i] - cleaned[i];  // echo estimate W·x
      dot += mic[i] * e;
      mm += mic[i] * mic[i];
      ee += e * e;
    }
    double rho = dot / (sqrt(mm * ee) + 1e-12);
    if (rho < d->threshold) d->hangover = d->hangoverBlocks;
  }
  if (d->hangover > 0) d->hangover -= 1;
}

void aec_dtd_reset(AecDtd* d) {
  if (!d) return;
  d->block = 0;
  d->hangover = 0;
}

void aec_dtd_destroy(AecDtd* d) { free(d); }

// --- Residual echo suppressor (port of aec_offline.dart's ResidualEchoSuppressor)
//
// A Wiener-style spectral post-filter on what the linear canceller leaves
// (filter misadjustment, the echo tail beyond the filter). Framing reuses the
// canceller's own overlap-save structure — a 2*blockSize [prev ; cur] frame,
// spectrally gained, keep the last block — so there's no window/COLA
// bookkeeping. Per bin the residual echo is lambda(k)*|Y(k)|^2 with the echo
// leakage lambda learned ONLY on far-end single-talk (pass updateLeak=0 during
// double-talk, else the near-end drives lambda far too high).

struct AecRes {
  int blockSize;
  int n;  // 2*blockSize
  double overSubtract;
  double gainFloor;
  double powerSmoothing;
  double leakSmoothing;
  double eps;
  double* prevCleaned;  // b
  double* prevEcho;     // b
  double* pe;           // n — smoothed residual power
  double* py;           // n — smoothed echo-estimate power
  double* leak;         // n — lambda per bin
  // Scratch (reused per block).
  double* eRe;  // n
  double* eIm;  // n
  double* yRe;  // n
  double* yIm;  // n
};

AecRes* aec_res_create(int blockSize, double overSubtract, double gainFloor,
                       double powerSmoothing, double leakSmoothing,
                       double eps) {
  if (!is_pow2(blockSize)) return NULL;
  AecRes* r = (AecRes*)calloc(1, sizeof(AecRes));
  if (!r) return NULL;
  r->blockSize = blockSize;
  r->n = 2 * blockSize;
  r->overSubtract = overSubtract;
  r->gainFloor = gainFloor;
  r->powerSmoothing = powerSmoothing;
  r->leakSmoothing = leakSmoothing;
  r->eps = eps;
  int b = blockSize, n = r->n;
  r->prevCleaned = (double*)calloc((size_t)b, sizeof(double));
  r->prevEcho = (double*)calloc((size_t)b, sizeof(double));
  r->pe = (double*)calloc((size_t)n, sizeof(double));
  r->py = (double*)calloc((size_t)n, sizeof(double));
  r->leak = (double*)calloc((size_t)n, sizeof(double));
  r->eRe = (double*)calloc((size_t)n, sizeof(double));
  r->eIm = (double*)calloc((size_t)n, sizeof(double));
  r->yRe = (double*)calloc((size_t)n, sizeof(double));
  r->yIm = (double*)calloc((size_t)n, sizeof(double));
  if (!r->prevCleaned || !r->prevEcho || !r->pe || !r->py || !r->leak ||
      !r->eRe || !r->eIm || !r->yRe || !r->yIm) {
    aec_res_destroy(r);
    return NULL;
  }
  return r;
}

AecRes* aec_res_create_default(int blockSize) {
  // Mirrors the Dart ResidualEchoSuppressor defaults.
  return aec_res_create(blockSize, 1.0, 0.1, 0.8, 0.95, 1e-12);
}

void aec_res_process(AecRes* r, const double* cleaned, const double* echoEst,
                     int updateLeak, double* out) {
  const int b = r->blockSize, n = r->n;
  double* eRe = r->eRe;
  double* eIm = r->eIm;
  double* yRe = r->yRe;
  double* yIm = r->yIm;

  // Overlap-save frames: [previous ; current].
  memset(eIm, 0, n * sizeof(double));
  memset(yIm, 0, n * sizeof(double));
  for (int i = 0; i < b; i++) {
    eRe[i] = r->prevCleaned[i];
    eRe[b + i] = cleaned[i];
    yRe[i] = r->prevEcho[i];
    yRe[b + i] = echoEst[i];
  }
  aec_fft(eRe, eIm, n);
  aec_fft(yRe, yIm, n);

  for (int k = 0; k < n; k++) {
    double pe = eRe[k] * eRe[k] + eIm[k] * eIm[k];
    double py = yRe[k] * yRe[k] + yIm[k] * yIm[k];
    r->pe[k] = r->powerSmoothing * r->pe[k] + (1 - r->powerSmoothing) * pe;
    r->py[k] = r->powerSmoothing * r->py[k] + (1 - r->powerSmoothing) * py;

    if (updateLeak && r->py[k] > r->eps) {
      double ratio = r->pe[k] / (r->py[k] + r->eps);
      if (ratio < 0.0) ratio = 0.0;
      if (ratio > 1.0) ratio = 1.0;
      r->leak[k] =
          r->leakSmoothing * r->leak[k] + (1 - r->leakSmoothing) * ratio;
    }

    double residual = r->overSubtract * r->leak[k] * r->py[k];
    double gain = 1.0 - residual / (r->pe[k] + r->eps);
    if (gain < r->gainFloor) gain = r->gainFloor;
    if (gain > 1.0) gain = 1.0;
    eRe[k] *= gain;
    eIm[k] *= gain;
  }

  ifft(eRe, eIm, n);

  // Overlap-save: the last block is the valid output.
  for (int i = 0; i < b; i++) out[i] = eRe[b + i];
  for (int i = 0; i < b; i++) {
    r->prevCleaned[i] = cleaned[i];
    r->prevEcho[i] = echoEst[i];
  }
}

void aec_res_reset(AecRes* r) {
  if (!r) return;
  int b = r->blockSize, n = r->n;
  memset(r->prevCleaned, 0, b * sizeof(double));
  memset(r->prevEcho, 0, b * sizeof(double));
  memset(r->pe, 0, n * sizeof(double));
  memset(r->py, 0, n * sizeof(double));
  memset(r->leak, 0, n * sizeof(double));
}

void aec_res_destroy(AecRes* r) {
  if (!r) return;
  free(r->prevCleaned);
  free(r->prevEcho);
  free(r->pe);
  free(r->py);
  free(r->leak);
  free(r->eRe);
  free(r->eIm);
  free(r->yRe);
  free(r->yIm);
  free(r);
}
