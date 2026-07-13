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
// cleaned and raw are audio-writes / Dart-reads. Acquire/release on the two
// indices is enough — no locks, safe to touch from the realtime callback.
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
static int ring_drain(Ring* r, int16_t* out, int maxFrames) {
  int i = 0;
  for (; i < maxFrames; i++) {
    if (!ring_pop(r, &out[i])) break;
  }
  return i;
}

// ---- engine -----------------------------------------------------------------

struct AecEngine {
  int sampleRate;
  int frame;   // AEC block size
  int period;  // device frames per callback (defaults to frame)
  AecDsp* aec;
  ma_device device;
  ma_context context;
  int started;
  int hasContext;

  Ring refRing;      // Dart -> audio (reference to play + cancel)
  Ring cleanedRing;  // audio -> Dart (near-end estimate)
  Ring rawRing;      // audio -> Dart (raw mic, diagnostics)

  // Block accumulators, touched only by whoever runs the sample loop.
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

// The shared per-sample core, used identically by the realtime callback and the
// test pump. For each frame: pull the reference we owe the speaker, (optionally)
// play it, tap the raw mic, and once a full AEC block has accumulated, cancel
// and push the cleaned near-end. `spk` may be NULL (test pump / capture-only).
static void engine_run(AecEngine* e, const int16_t* mic, int16_t* spk,
                       ma_uint32 frameCount) {
  for (ma_uint32 i = 0; i < frameCount; i++) {
    int16_t r = 0;
    ring_pop(&e->refRing, &r);  // reference for this instant (0 on underrun)
    if (spk) spk[i] = r;        // play it out the speaker

    int16_t m = mic ? mic[i] : 0;
    ring_push(&e->rawRing, m);  // raw pre-cancellation mic tap (diagnostics)

    // Accumulate the sample-aligned (reference, mic) pair into the AEC block.
    e->refBlock[e->fill] = r / 32768.0;
    e->micBlock[e->fill] = m / 32768.0;
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

// Realtime duplex callback: aligned (mic in, speaker out) on one clock.
static void data_cb(ma_device* dev, void* pOutput, const void* pInput,
                    ma_uint32 frameCount) {
  AecEngine* e = (AecEngine*)dev->pUserData;
  engine_run(e, (const int16_t*)pInput, (int16_t*)pOutput, frameCount);
}

AecEngine* aec_engine_create(int sampleRate, int frame) {
  if (sampleRate <= 0 || frame <= 0 || (frame & (frame - 1)) != 0) return NULL;
  AecEngine* e = (AecEngine*)calloc(1, sizeof(AecEngine));
  if (!e) return NULL;
  e->sampleRate = sampleRate;
  e->frame = frame;
  e->period = frame;  // default: one AEC block per callback
  e->aec = aec_dsp_create_default(frame);
  e->micBlock = (double*)calloc((size_t)frame, sizeof(double));
  e->refBlock = (double*)calloc((size_t)frame, sizeof(double));
  e->outBlock = (double*)calloc((size_t)frame, sizeof(double));

  // ~1 s of buffering each way (rounded up to a power of two) — slack for
  // scheduling jitter, and enough that a batch test can pump a second of audio
  // before it must drain.
  int cap = next_pow2(sampleRate);
  int okRings = ring_init(&e->refRing, cap) == 0 &&
                ring_init(&e->cleanedRing, cap) == 0 &&
                ring_init(&e->rawRing, cap) == 0;

  if (!e->aec || !e->micBlock || !e->refBlock || !e->outBlock || !okRings) {
    aec_engine_destroy(e);
    return NULL;
  }
  return e;
}

// Fill a device config with our fixed s16/mono/duplex parameters.
static ma_device_config base_config(AecEngine* e) {
  ma_device_config cfg = ma_device_config_init(ma_device_type_duplex);
  cfg.sampleRate = (ma_uint32)e->sampleRate;
  cfg.capture.format = ma_format_s16;
  cfg.capture.channels = 1;
  cfg.playback.format = ma_format_s16;
  cfg.playback.channels = 1;
  cfg.periodSizeInFrames = (ma_uint32)e->period;
  cfg.dataCallback = data_cb;
  cfg.pUserData = e;
  return cfg;
}

static int start_with_config(AecEngine* e, ma_context* ctx,
                             ma_device_config* cfg) {
  ma_result r = ma_device_init(ctx, cfg, &e->device);
  if (r != MA_SUCCESS) return (int)r;
  r = ma_device_start(&e->device);
  if (r != MA_SUCCESS) {
    ma_device_uninit(&e->device);
    return (int)r;
  }
  e->started = 1;
  return 0;
}

int aec_engine_start(AecEngine* e) {
  if (!e) return -1;
  if (e->started) return 0;
  ma_device_config cfg = base_config(e);
  return start_with_config(e, NULL, &cfg);
}

int aec_engine_start_named(AecEngine* e, const char* playbackName,
                           const char* captureName) {
  if (!e) return -1;
  if (e->started) return 0;

  ma_result r = ma_context_init(NULL, 0, NULL, &e->context);
  if (r != MA_SUCCESS) return (int)r;
  e->hasContext = 1;

  ma_device_info* playbackInfos = NULL;
  ma_device_info* captureInfos = NULL;
  ma_uint32 playbackCount = 0, captureCount = 0;
  r = ma_context_get_devices(&e->context, &playbackInfos, &playbackCount,
                             &captureInfos, &captureCount);
  if (r != MA_SUCCESS) {
    ma_context_uninit(&e->context);
    e->hasContext = 0;
    return (int)r;
  }

  ma_device_id* playbackId = NULL;
  ma_device_id* captureId = NULL;
  if (playbackName) {
    for (ma_uint32 i = 0; i < playbackCount; i++) {
      if (strstr(playbackInfos[i].name, playbackName)) {
        playbackId = &playbackInfos[i].id;
        break;
      }
    }
  }
  if (captureName) {
    for (ma_uint32 i = 0; i < captureCount; i++) {
      if (strstr(captureInfos[i].name, captureName)) {
        captureId = &captureInfos[i].id;
        break;
      }
    }
  }
  // If a name was requested but not found, fail loudly rather than silently
  // grabbing the default (which for capture would be the real mic).
  if ((playbackName && !playbackId) || (captureName && !captureId)) {
    ma_context_uninit(&e->context);
    e->hasContext = 0;
    return -2;
  }

  ma_device_config cfg = base_config(e);
  cfg.playback.pDeviceID = playbackId;
  cfg.capture.pDeviceID = captureId;
  int rc = start_with_config(e, &e->context, &cfg);
  if (rc != 0) {
    ma_context_uninit(&e->context);
    e->hasContext = 0;
  }
  return rc;
}

int aec_engine_start_null(AecEngine* e) {
  if (!e) return -1;
  if (e->started) return 0;
  ma_backend backends[] = {ma_backend_null};
  ma_result r = ma_context_init(backends, 1, NULL, &e->context);
  if (r != MA_SUCCESS) return (int)r;
  e->hasContext = 1;
  ma_device_config cfg = base_config(e);
  int rc = start_with_config(e, &e->context, &cfg);
  if (rc != 0) {
    ma_context_uninit(&e->context);
    e->hasContext = 0;
  }
  return rc;
}

void aec_engine_set_period(AecEngine* e, int period) {
  if (e && !e->started && period > 0) e->period = period;
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

void aec_engine_test_pump(AecEngine* e, const int16_t* mic, int frames) {
  if (!e || !mic || frames <= 0) return;
  engine_run(e, mic, NULL, (ma_uint32)frames);
}

int aec_engine_read(AecEngine* e, int16_t* out, int maxFrames) {
  if (!e || !out || maxFrames <= 0) return 0;
  return ring_drain(&e->cleanedRing, out, maxFrames);
}

int aec_engine_read_raw(AecEngine* e, int16_t* out, int maxFrames) {
  if (!e || !out || maxFrames <= 0) return 0;
  return ring_drain(&e->rawRing, out, maxFrames);
}

int aec_engine_stop(AecEngine* e) {
  if (!e) return 0;
  if (e->started) {
    ma_device_uninit(&e->device);  // stops then frees the device
    e->started = 0;
  }
  if (e->hasContext) {
    ma_context_uninit(&e->context);
    e->hasContext = 0;
  }
  return 0;
}

void aec_engine_destroy(AecEngine* e) {
  if (!e) return;
  aec_engine_stop(e);
  aec_dsp_destroy(e->aec);
  ring_free(&e->refRing);
  ring_free(&e->cleanedRing);
  ring_free(&e->rawRing);
  free(e->micBlock);
  free(e->refBlock);
  free(e->outBlock);
  free(e);
}

int aec_engine_sample_rate(const AecEngine* e) { return e ? e->sampleRate : 0; }
int aec_engine_frame(const AecEngine* e) { return e ? e->frame : 0; }
