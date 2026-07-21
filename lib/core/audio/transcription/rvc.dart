// lib/core/audio/transcription/rvc.dart
//
// RVC (Retrieval-based Voice Conversion) generator — the pure-Dart OFFLINE
// reference. Given ContentVec features (hubert.dart) + an F0 track (RMVPE) + a
// target speaker id, the RVC NSF-HiFi-GAN+flow generator produces converted
// audio. onnx_runtime_dart runs the full 4938-node graph at cosine 0.99994 vs
// onnxruntime — but at ~152× slower than real-time, so this path is OFFLINE-ONLY
// (a whole-clip conversion, or the web fallback). REAL-TIME RVC belongs on the
// native (CrispASR) path; this file is the SPEC that native must match — the
// exact coarse-pitch mapping, the 2× feature upsample, and the input tensors.
//
// The generator weights are user-supplied + LICENCE-GATED (RVC voice models are
// NC / per-model) — see `rvc_model_store.dart`. This file is model-free and pure.
//
// WEB-SAFE: takes a preloaded [OnnxModel].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/voice.dart'
    show ContentFeatures, VoiceConverter;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// RVC's F0-to-coarse-pitch bins: `f0 → mel → 1..255` (0 for unvoiced). The
/// generator's `pitch` input. mel range is fixed to 50–1100 Hz per RVC.
Int64List rvcCoarsePitch(Float32List f0Hz) {
  const f0Min = 50.0, f0Max = 1100.0;
  final melMin = 1127.0 * math.log(1.0 + f0Min / 700.0);
  final melMax = 1127.0 * math.log(1.0 + f0Max / 700.0);
  final out = Int64List(f0Hz.length);
  for (var i = 0; i < f0Hz.length; i++) {
    final f0 = f0Hz[i];
    if (f0 <= 0) {
      out[i] = 0; // unvoiced
      continue;
    }
    final mel = 1127.0 * math.log(1.0 + f0 / 700.0);
    final c = ((mel - melMin) * 254.0 / (melMax - melMin) + 1.0).round();
    out[i] = c.clamp(1, 255);
  }
  return out;
}

/// Upsample ContentVec [features] (50 fps) by 2× (nearest — RVC's `repeat`) to
/// 100 fps, then trim to [targetFrames] (the F0 frame count). Returns the packed
/// `[targetFrames × dim]` feature buffer aligned with the F0 track.
Float32List rvcAlignFeatures(ContentFeatures features, int targetFrames) {
  final d = features.dim;
  final src = features.feats;
  final out = Float32List(targetFrames * d);
  for (var t = 0; t < targetFrames; t++) {
    // 2× upsample: frame t of the 100 fps grid maps to 50 fps frame t~/2.
    final s = math.min(t ~/ 2, features.frames - 1);
    if (s < 0) continue;
    out.setRange(t * d, t * d + d, src, s * d);
  }
  return out;
}

/// Deterministic (seeded) flow noise `[1,192,T]` — RVC uses `randn`; a seed keeps
/// a conversion reproducible. Override via the `rnd` arg of [rvcConvert].
Float32List rvcSeededNoise(int frames, {int seed = 1234567}) {
  final rng = math.Random(seed);
  final out = Float32List(192 * frames);
  for (var i = 0; i < out.length; i++) {
    // Box–Muller for a normal-ish draw (RVC's rnd is standard normal).
    final u1 = rng.nextDouble().clamp(1e-9, 1.0);
    final u2 = rng.nextDouble();
    out[i] = math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
  return out;
}

/// Convert with an RVC generator [model]. [features] and [f0Hz] must already be
/// aligned to the SAME frame count (use [rvcAlignFeatures]); [speakerId] selects
/// the target voice. [rnd] overrides the flow noise (Site A, a graph input).
///
/// [sourceNoise] injects **Site B** — the SineGen additive noise the decoder's
/// NSF source draws inside the graph (a big `RandomNormal`, `(1, T×upp, 1)`,
/// voicing-dependent, genuinely random). onnx_runtime_dart mean-fills that node
/// by default (≈ zeros); passing a buffer routes it there via [OnnxRandomInject]
/// (length-matched, so the tiny phase `RandomUniform` is untouched), so a
/// determinism harness can feed the exact buffer the Python reference used and
/// line up bit-for-bit. A TEST affordance — production `convert()` leaves it null
/// (stays random-per-graph). Returns audio at [outSampleRate] (RVC v2 = 40 kHz).
({Float64List audio, int sampleRate}) rvcConvert(
  ContentFeatures features,
  Float32List f0Hz,
  int speakerId, {
  required OnnxModel model,
  int outSampleRate = 40000,
  Float32List? rnd,
  Float32List? sourceNoise,
}) {
  final t = f0Hz.length;
  final phone = features.frames == t && features.dim == 256
      ? features.feats
      : rvcAlignFeatures(features, t);
  final pitch = rvcCoarsePitch(f0Hz);
  final noise = rnd ?? rvcSeededNoise(t);
  final inputs = {
    'phone': Tensor.float(phone, [1, t, 256]),
    'phone_lengths': Tensor.int64(Int64List.fromList([t]), [1]),
    'pitch': Tensor.int64(pitch, [1, t]),
    'pitchf': Tensor.float(f0Hz, [1, t]),
    'ds': Tensor.int64(Int64List.fromList([speakerId]), [1]),
    'rnd': Tensor.float(noise, [1, 192, t]),
  };
  // Inject Site-B noise (if given) around this run only; restore after.
  final prevInject = OnnxRandomInject.provider;
  if (sourceNoise != null) {
    OnnxRandomInject.provider =
        (op, shape) => op == 'RandomNormal' ? sourceNoise : null;
  }
  final Tensor a;
  try {
    a = model.run(inputs, const ['audio'])['audio']!;
  } finally {
    OnnxRandomInject.provider = prevInject;
  }
  final f = a.f ?? a.asFloatList();
  final audio = Float64List(f.length);
  for (var i = 0; i < f.length; i++) {
    audio[i] = f[i];
  }
  return (audio: audio, sampleRate: outSampleRate);
}

/// Wrap a loaded RVC [model] as the [VoiceConverter] seam. Offline-only.
VoiceConverter rvcConverter(OnnxModel model, {int outSampleRate = 40000}) =>
    (features, f0Hz, speakerId) async => rvcConvert(
          features,
          f0Hz,
          speakerId,
          model: model,
          outSampleRate: outSampleRate,
        );
