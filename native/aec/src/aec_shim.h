// aec_shim.h — the C surface Dart's AecEngine binds over FFI.
//
// Two layers, cleanly separated:
//   * aec_dsp_* (aec_dsp.h) — the pure MIT echo-canceller, no audio device.
//     Offline-testable; this is what the ERLE cross-check exercises.
//   * aec_engine_* (here) — a full-duplex host built on miniaudio (MIT-0): one
//     ma_device in duplex mode owns playback AND capture on a single hardware
//     clock, so the reference (what we play) and the mic are sample-aligned —
//     the alignment that Flutter's separate audioplayers/record plugins cannot
//     provide (see AEC_TIER3B.md). The device callback pulls the app's queued
//     reference, plays it, uses the *same* samples as the AEC far-end, and
//     pushes the cleaned near-end to a ring the Dart side drains.
//
// All engine calls are safe to make from the Dart isolate thread; the audio
// callback runs on miniaudio's realtime thread and communicates only through
// lock-free single-producer/single-consumer rings (no malloc, no locks).

#ifndef AEC_SHIM_H
#define AEC_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AecEngine AecEngine;

// Create (but don't start) a duplex engine. `frame` is the AEC block size
// (power of two, e.g. 256); the adaptive filter covers ~frame/sampleRate of
// echo tail. Returns NULL on bad args or allocation failure.
AecEngine* aec_engine_create(int sampleRate, int frame);

// Open + start the full-duplex device. Returns 0 on success, non-zero
// (a miniaudio ma_result) on failure — e.g. no mic permission / no device.
int aec_engine_start(AecEngine* e);

// Queue mono PCM16 to be played out the speaker AND cancelled from the mic.
// Non-blocking; on ring overflow the oldest queued reference is dropped (better
// a glitch than unbounded latency). `frames` = number of int16 samples.
void aec_engine_reference(AecEngine* e, const int16_t* pcm, int frames);

// Drain cleaned near-end PCM16 (mono). Writes up to `maxFrames` samples to
// `out`, returns the count written (0 when nothing is ready yet).
int aec_engine_read(AecEngine* e, int16_t* out, int maxFrames);

// Stop the device (safe if not started). Returns 0 on success.
int aec_engine_stop(AecEngine* e);

// Stop if needed, then free everything. Safe on NULL.
void aec_engine_destroy(AecEngine* e);

// Introspection for tests/diagnostics.
int aec_engine_sample_rate(const AecEngine* e);
int aec_engine_frame(const AecEngine* e);

#ifdef __cplusplus
}
#endif

#endif  // AEC_SHIM_H
