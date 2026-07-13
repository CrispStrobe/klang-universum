// aec_shim.c — full-duplex host wiring the MIT AEC core to a miniaudio device.
// See aec_shim.h. Ours (MIT); miniaudio.h is MIT-0.

#include "aec_shim.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "aec_dsp.h"

// miniaudio.h is included for declarations only here; MA_IMPLEMENTATION lives in
// miniaudio_impl.c so the 4MB header compiles exactly once.
#include "vendor/miniaudio.h"

// ---- lock-free SPSC ring of int16 (power-of-two capacity) -------------------
//
// One producer, one consumer per ring: reference is Dart-writes / audio-reads;
// cleaned is audio-writes / Dart-reads. Acquire/release on the two indices is
// enough — no locks, safe to touch from the realtime callback.
typedef struct {
  int16_t* buf;
  int mask;  // capacity-1
  atomic_int head;  // next write (producer)
  atomic_int tail;  // next read  (consumer)
} Ring;

static int ring_init(Ring* r, int capacityPow2) {
  r->buf = (int16_t*)calloc((size_t)capacityPow2, sizeof(int16_t));
  if (!r->buf) return -1;
  r->mask = capacityPow2 - 1;
  atomic_init(&r->head, 0);
  atomic_init(&r->tail, 0);
  return 0;
}
static void ring_free(Ring* r) {
  free(r->buf);
  r->buf = NULL;
}
// Push one sample; returns 0 if full (caller decides drop policy).
static int ring_push(Ring* r, int16_t v) {
  int head = atomic_load_explicit(&r->head, memory_order_relaxed);
  int next = (head + 1) & r->mask;
  if (next == atomic_load_explicit(&r->tail, memory_order_acquire)) return 0;
  r->buf[head] = v;
  atomic_store_explicit(&r->head, next, memory_order_release);
  return 1;
}
// Pop one sample into *v; returns 0 if empty.
static int ring_pop(Ring* r, int16_t* v) {
  int tail = atomic_load_explicit(&r->tail, memory_order_relaxed);
  if (tail == atomic_load_explicit(&r->head, memory_order_acquire)) return 0;
  *v = r->buf[tail];
  atomic_store_explicit(&r->tail, (tail + 1) & r->mask, memory_order_release);
  return 1;
}

// ---- engine -----------------------------------------------------------------

struct AecEngine {
  int sampleRate;
  int frame;  // AEC block size
  AecDsp* aec;
  ma_device device;
  int started;

  Ring refRing;      // Dart -> audio (reference to play + cancel)
  Ring cleanedRing;  // audio -> Dart (near-end estimate)

  // Block accumulators, touched only by the audio callback.
  double* micBlock;
  double* refBlock;
  double* outBlock;
  int fill;
};

// Smallest power of two >= v (v>0).
static int next_pow2(int v) {
  int p = 1;
  while (p < v) p <<= 1;
  return p;
}

static int16_t clamp_i16(double v) {
  long iv = lround(v);
  if (iv > 32767) iv = 32767;
  if (iv < -32768) iv = -32768;
  return (int16_t)iv;
}

// Realtime duplex callback: aligned (mic in, speaker out) on one clock.
static void data_cb(ma_device* dev, void* pOutput, const void* pInput,
                    ma_uint32 frameCount) {
  AecEngine* e = (AecEngine*)dev->pUserData;
  const int16_t* mic = (const int16_t*)pInput;
  int16_t* spk = (int16_t*)pOutput;

  for (ma_uint32 i = 0; i < frameCount; i++) {
    int16_t r = 0;
    ring_pop(&e->refRing, &r);  // reference for this instant (0 on underrun)
    spk[i] = r;                 // play it out the speaker

    // Accumulate the sample-aligned (reference, mic) pair into the AEC block.
    e->refBlock[e->fill] = r / 32768.0;
    e->micBlock[e->fill] = (mic ? mic[i] : 0) / 32768.0;
    e->fill++;

    if (e->fill == e->frame) {
      aec_dsp_process(e->aec, e->refBlock, e->micBlock, e->outBlock);
      for (int j = 0; j < e->frame; j++) {
        ring_push(&e->cleanedRing, clamp_i16(e->outBlock[j] * 32768.0));
      }
      e->fill = 0;
    }
  }
}

AecEngine* aec_engine_create(int sampleRate, int frame) {
  if (sampleRate <= 0 || frame <= 0 || (frame & (frame - 1)) != 0) return NULL;
  AecEngine* e = (AecEngine*)calloc(1, sizeof(AecEngine));
  if (!e) return NULL;
  e->sampleRate = sampleRate;
  e->frame = frame;
  e->aec = aec_dsp_create_default(frame);
  e->micBlock = (double*)calloc((size_t)frame, sizeof(double));
  e->refBlock = (double*)calloc((size_t)frame, sizeof(double));
  e->outBlock = (double*)calloc((size_t)frame, sizeof(double));

  // ~0.5 s of buffering each way (rounded up to a power of two) — enough slack
  // for scheduling jitter without adding audible latency.
  int cap = next_pow2(sampleRate / 2);
  int okRings = ring_init(&e->refRing, cap) == 0 &&
                ring_init(&e->cleanedRing, cap) == 0;

  if (!e->aec || !e->micBlock || !e->refBlock || !e->outBlock || !okRings) {
    aec_engine_destroy(e);
    return NULL;
  }
  return e;
}

int aec_engine_start(AecEngine* e) {
  if (!e) return -1;
  if (e->started) return 0;

  ma_device_config cfg = ma_device_config_init(ma_device_type_duplex);
  cfg.sampleRate = (ma_uint32)e->sampleRate;
  cfg.capture.format = ma_format_s16;
  cfg.capture.channels = 1;
  cfg.playback.format = ma_format_s16;
  cfg.playback.channels = 1;
  cfg.periodSizeInFrames = (ma_uint32)e->frame;
  cfg.dataCallback = data_cb;
  cfg.pUserData = e;

  ma_result r = ma_device_init(NULL, &cfg, &e->device);
  if (r != MA_SUCCESS) return (int)r;
  r = ma_device_start(&e->device);
  if (r != MA_SUCCESS) {
    ma_device_uninit(&e->device);
    return (int)r;
  }
  e->started = 1;
  return 0;
}

void aec_engine_reference(AecEngine* e, const int16_t* pcm, int frames) {
  if (!e || !pcm) return;
  for (int i = 0; i < frames; i++) {
    if (!ring_push(&e->refRing, pcm[i])) {
      // Full: drop the oldest to bound latency, then retry once.
      int16_t discard;
      ring_pop(&e->refRing, &discard);
      ring_push(&e->refRing, pcm[i]);
    }
  }
}

int aec_engine_read(AecEngine* e, int16_t* out, int maxFrames) {
  if (!e || !out || maxFrames <= 0) return 0;
  int i = 0;
  for (; i < maxFrames; i++) {
    if (!ring_pop(&e->cleanedRing, &out[i])) break;
  }
  return i;
}

int aec_engine_stop(AecEngine* e) {
  if (!e || !e->started) return 0;
  ma_device_uninit(&e->device);  // stops then frees the device
  e->started = 0;
  return 0;
}

void aec_engine_destroy(AecEngine* e) {
  if (!e) return;
  aec_engine_stop(e);
  aec_dsp_destroy(e->aec);
  ring_free(&e->refRing);
  ring_free(&e->cleanedRing);
  free(e->micBlock);
  free(e->refBlock);
  free(e->outBlock);
  free(e);
}

int aec_engine_sample_rate(const AecEngine* e) { return e ? e->sampleRate : 0; }
int aec_engine_frame(const AecEngine* e) { return e ? e->frame : 0; }
