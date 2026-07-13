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

// Override the device period (frames per callback), decoupling it from the AEC
// block size. A SHORT period keeps device latency low, which keeps the acoustic
// round-trip delay small; a LONGER `frame` (AEC block) then covers that delay
// with room to spare. Must be called before start; period defaults to `frame`.
// No-op if period <= 0.
void aec_engine_set_period(AecEngine* e, int period);

// Open + start the full-duplex device on the system DEFAULT playback+capture.
// Returns 0 on success, non-zero (a miniaudio ma_result) on failure — e.g. no
// mic permission / no device.
int aec_engine_start(AecEngine* e);

// Start on named devices (substring match against miniaudio's device names),
// leaving the system defaults untouched. Pass NULL for either to use its
// default. Used by the BlackHole loopback live test to route both playback and
// capture through the loopback device without switching the system default.
int aec_engine_start_named(AecEngine* e, const char* playbackName,
                           const char* captureName);

// Start on the miniaudio `null` backend: a silent device whose callback still
// fires on a timer. Exercises the full duplex lifecycle + ring/threading path
// headlessly, with no real hardware and no mic-permission prompt.
int aec_engine_start_null(AecEngine* e);

// Queue mono PCM16 to be played out the speaker AND cancelled from the mic.
// Non-blocking; on ring overflow the oldest queued reference is dropped (better
// a glitch than unbounded latency). `frames` = number of int16 samples.
void aec_engine_reference(AecEngine* e, const int16_t* pcm, int frames);

// Drain cleaned near-end PCM16 (mono). Writes up to `maxFrames` samples to
// `out`, returns the count written (0 when nothing is ready yet).
int aec_engine_read(AecEngine* e, int16_t* out, int maxFrames);

// Drain the RAW mic (pre-cancellation) PCM16 the callback captured — a
// diagnostic tap for tests: comparing raw vs cleaned energy gives ERLE, and
// cross-correlating raw vs the reference gives the loopback delay. Same
// semantics as aec_engine_read.
int aec_engine_read_raw(AecEngine* e, int16_t* out, int maxFrames);

// TEST HOOK — run `frames` of `mic` PCM16 through the EXACT processing the
// realtime callback runs (pull the queued reference, cancel, push cleaned/raw),
// with no audio device. Lets a unit test verify the int16 ring/framing/
// conversion data path deterministically. Queue the reference first with
// aec_engine_reference(); mic and reference are consumed 1:1 in order.
void aec_engine_test_pump(AecEngine* e, const int16_t* mic, int frames);

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
