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

  if (!a->wRe || !a->wIm || !a->xPrev || !a->power || !a->xRe || !a->xIm ||
      !a->yRe || !a->yIm || !a->eRe || !a->eIm || !a->gRe || !a->gIm) {
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

  // Far-end VAD: pause learning when the reference is (near) silent.
  double refMs = 0.0;
  for (int i = 0; i < b; i++) refMs += reference[i] * reference[i];
  if (refMs / b < a->farEndFloor) {
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

  // NLMS gradient G = mu . conj(X) . E / (smoothedPower + reg), per bin.
  for (int k = 0; k < n; k++) {
    double p = xRe[k] * xRe[k] + xIm[k] * xIm[k];
    a->power[k] = a->powerSmoothing * a->power[k] + (1 - a->powerSmoothing) * p;
    double norm = a->mu / (a->power[k] + reg);
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
  free(a);
}
