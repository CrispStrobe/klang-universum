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

// Zero the adaptive filter and history (EchoCanceller.reset).
void aec_dsp_reset(AecDsp* a);

void aec_dsp_destroy(AecDsp* a);

// Exposed for the FFT self-check / reuse. In-place radix-2 Cooley-Tukey FFT;
// `n` must be a power of two. Direct port of chroma_analysis.dart's fft().
void aec_fft(double* re, double* im, int n);

#ifdef __cplusplus
}
#endif

#endif  // AEC_DSP_H
