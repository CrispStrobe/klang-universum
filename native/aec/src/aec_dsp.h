// aec_dsp.h — cleanroom C port of the pure-Dart AEC core.
//
// This is a direct, line-for-line port of lib/core/audio/echo_canceller.dart
// (the constrained overlap-save FDAF + NLMS linear echo canceller) and the
// radix-2 FFT from lib/core/audio/chroma_analysis.dart. Both are our own MIT
// code — nothing here is derived from a third-party library, so the whole DSP
// core stays MIT-clean. Keeping the algorithm identical to the Dart original is
// deliberate: the offline test cross-checks the C output against the Dart core's
// proven ERLE (test/echo_canceller_test.dart), so a port bug shows up as a
// diverging ERLE rather than passing silently.
//
// No audio device, no platform dependency: this compiles anywhere and is what
// the FFI offline ERLE test exercises. The miniaudio full-duplex host lives in
// aec_shim.c and merely feeds aligned blocks into aec_process().

#ifndef AEC_DSP_H
#define AEC_DSP_H

#ifdef __cplusplus
extern "C" {
#endif

// Opaque adaptive-filter state (one speaker->mic path estimate).
typedef struct AecDsp AecDsp;

// Create a canceller. Defaults mirror EchoCanceller's Dart constructor:
//   blockSize=1024, mu=0.7, powerSmoothing=0.9, eps=1e-6,
//   farEndFloor=1e-5, regFactor=1.0, leak=1e-3.
// blockSize must be a power of two (the FFT size is 2*blockSize). Returns NULL
// on allocation failure or a non-power-of-two blockSize.
AecDsp* aec_dsp_create(int blockSize, double mu, double powerSmoothing,
                       double eps, double farEndFloor, double regFactor,
                       double leak);

// Convenience: create with the Dart EchoCanceller defaults for `blockSize`.
AecDsp* aec_dsp_create_default(int blockSize);

int aec_dsp_block_size(const AecDsp* a);

// Cancel the echo of `reference` from `mic`, both `blockSize` long and
// time-aligned (same block index), writing the near-end estimate to `out`
// (`blockSize` long, may alias neither input). Mirrors EchoCanceller.process.
void aec_dsp_process(AecDsp* a, const double* reference, const double* mic,
                     double* out);

// Gate the NLMS filter update: adapt!=0 learns (default); adapt==0 FREEZES the
// filter for subsequent blocks (still cancels with the current coefficients but
// doesn't learn) — how the double-talk detector protects the filter from
// adapting on near-end speech. Additive: default behaviour is unchanged, so the
// Dart↔C ERLE cross-check still holds.
void aec_dsp_set_adapt(AecDsp* a, int adapt);

// Zero the adaptive filter and history (EchoCanceller.reset).
void aec_dsp_reset(AecDsp* a);

void aec_dsp_destroy(AecDsp* a);

// --- Adaptive learning rate (port of echo_canceller.dart's AdaptiveLearningRate)
// Closed-loop control of the NLMS step (Valin, IEEE TASLP 2007): the filter
// picks its own rate per bin per block from its live leakage estimate, instead
// of the fixed `mu` passed to aec_dsp_create. Attach one with aec_dsp_set_rate;
// with none attached (the default) the fixed-`mu` path is byte-identical, so the
// Dart↔C ERLE cross-check on that path still holds.
typedef struct AecRate AecRate;

// Create a rate controller. Defaults (via *_create_default) mirror the Dart:
//   muMax=0.5, initialMu=0.25, initBlocks=2, gamma=0.1, beta0=0.05, eps=1e-12.
// State is sized lazily on the first processed block (it learns the FFT size
// from the AecDsp it's attached to), so no block size is needed here.
AecRate* aec_rate_create(double muMax, double initialMu, int initBlocks,
                         double gamma, double beta0, double eps);
AecRate* aec_rate_create_default(void);

// The controller's current leakage estimate (the paper's eta = 1/ERLE) and the
// mean step it chose on the last block — diagnostics, matching the Dart fields.
double aec_rate_leakage(const AecRate* r);
double aec_rate_last_mean_mu(const AecRate* r);

void aec_rate_reset(AecRate* r);
void aec_rate_destroy(AecRate* r);

// Attach (rate!=NULL) or detach (NULL) a rate controller. While attached, the
// filter ignores its fixed `mu` and steers by the controller. Detaching restores
// the exact fixed-`mu` behaviour. The AecDsp does NOT take ownership — destroy
// the rate yourself.
void aec_dsp_set_rate(AecDsp* a, AecRate* rate);

// --- Double-talk detector (port of aec_offline.dart's DoubleTalkDetector) ----
// Decides, per block, whether to freeze the filter because near-end speech is
// present. Uses a normalized-correlation statistic (no echo-path-gain threshold
// to tune, unlike Geigel). Feed it `aec_dtd_update` after each processed block;
// read `aec_dtd_freeze` before the next to drive `aec_dsp_set_adapt`.
typedef struct AecDtd AecDtd;

// Create a detector. Defaults (via *_create_default) mirror the Dart:
//   threshold=0.9, hangoverBlocks=8, warmupBlocks=12, farEndFloor=1e-5.
AecDtd* aec_dtd_create(double threshold, int hangoverBlocks, int warmupBlocks,
                       double farEndFloor);
AecDtd* aec_dtd_create_default(void);

// 1 if the next block should freeze adaptation (a double-talk decision is held
// active by the hangover), else 0.
int aec_dtd_freeze(const AecDtd* d);

// Update the freeze state from a just-processed block: its `reference`, `mic`
// and `cleaned` output (all `blockSize` long).
void aec_dtd_update(AecDtd* d, const double* reference, const double* mic,
                    const double* cleaned, int blockSize);

void aec_dtd_reset(AecDtd* d);
void aec_dtd_destroy(AecDtd* d);

// --- Residual echo suppressor (port of aec_offline.dart's ResidualEchoSuppressor)
// A Wiener-style spectral post-filter on the linear canceller's residual, in the
// canceller's own overlap-save framing (reuses aec_fft/ifft). Feed it the
// cleaned block and the canceller's echo estimate (mic - cleaned) each block.
typedef struct AecRes AecRes;

// Create a suppressor. Defaults (via *_create_default) mirror the Dart:
//   overSubtract=1.0, gainFloor=0.1, powerSmoothing=0.8, leakSmoothing=0.95,
//   eps=1e-12. blockSize must be a power of two.
AecRes* aec_res_create(int blockSize, double overSubtract, double gainFloor,
                       double powerSmoothing, double leakSmoothing, double eps);
AecRes* aec_res_create_default(int blockSize);

// Suppress residual echo in one `cleaned` block, given the canceller's `echoEst`
// (mic - cleaned) for the same block. Both `blockSize` long; writes the
// suppressed block to `out` (`blockSize` long). Pass updateLeak=0 during
// double-talk so the near-end doesn't inflate the leakage estimate.
void aec_res_process(AecRes* r, const double* cleaned, const double* echoEst,
                     int updateLeak, double* out);

void aec_res_reset(AecRes* r);
void aec_res_destroy(AecRes* r);

// Exposed for the FFT self-check / reuse. In-place radix-2 Cooley-Tukey FFT;
// `n` must be a power of two. Direct port of chroma_analysis.dart's fft().
void aec_fft(double* re, double* im, int n);

#ifdef __cplusplus
}
#endif

#endif  // AEC_DSP_H
