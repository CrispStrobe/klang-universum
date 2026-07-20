// lib/core/audio/transcription/hubert.dart
//
// HuBERT / ContentVec content encoder — the linchpin of every singing-voice-
// conversion model (RVC, so-vits-svc, DDSP-SVC all consume its features). Takes
// 16 kHz mono audio → per-frame content features at 50 fps (one frame per 320
// samples), dim 256 (vec-256-layer-9) or 768 (vec-768-layer-12). Runs on
// `onnx_runtime_dart`; MIT weights (fairseq HuBERT + the ContentVec finetune).
//
// The model's exact input/output tensor names differ across community exports,
// so this wraps the model by INTROSPECTING its `inputSpecs`/`outputNames`
// (float audio input + an optional int length input) rather than hard-coding.
//
// WEB-SAFE: takes a preloaded [OnnxModel]; the ~360 MB download (dart:io) lives
// in `hubert_model_store.dart`. Voice conversion then feeds these features + an
// F0 track (RMVPE) + a speaker id to a [VoiceConverter].
library;

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/voice.dart'
    show ContentEncoder, ContentFeatures;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

const int hubertSampleRate = 16000;

/// Encode [mono] into HuBERT/ContentVec [ContentFeatures]. [model] is the
/// preloaded ContentVec ONNX. Pure / synchronous / web-safe.
ContentFeatures hubertEncodeSync(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = hubertSampleRate,
}) {
  final audio = sampleRate == hubertSampleRate
      ? mono
      : resampleLinear(mono, sampleRate / hubertSampleRate);
  final n = audio.length;
  if (n == 0) return (feats: Float32List(0), frames: 0, dim: 0);

  final f32 = Float32List(n);
  for (var i = 0; i < n; i++) {
    f32[i] = audio[i];
  }

  // Introspect: the float input is the audio; an int input (if any) is length.
  final specs = model.inputSpecs;
  final audioSpec = specs.firstWhere(
    (s) => !s.isInt,
    orElse: () => specs.first,
  );
  final rank = audioSpec.shape.length;
  final audioTensor = rank >= 3
      ? Tensor.float(f32, [1, 1, n]) // [batch, channel, samples]
      : Tensor.float(f32, [1, n]); // [batch, samples]

  final feed = <String, Tensor>{audioSpec.name: audioTensor};
  for (final s in specs) {
    if (s.isInt) {
      feed[s.name] = Tensor.int64(Int64List.fromList([n]), [1]);
    }
  }

  final outName = model.outputNames.first;
  final out = model.run(feed, [outName])[outName]!;
  final data = out.f ?? out.asFloatList();
  // Output is [1, frames, dim]; derive frames/dim from the tensor shape.
  final shape = out.shape;
  final dim = shape.last;
  final frames = data.length ~/ (dim == 0 ? 1 : dim);
  return (feats: Float32List.fromList(data), frames: frames, dim: dim);
}

/// Async wrapper fitting the [ContentEncoder] seam.
Future<ContentFeatures> hubertEncode(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = hubertSampleRate,
}) async =>
    hubertEncodeSync(mono, model: model, sampleRate: sampleRate);

/// Wrap a loaded [model] as the [ContentEncoder] seam the pipeline injects.
ContentEncoder hubertEncoder(OnnxModel model) => (mono, sampleRate) =>
    hubertEncode(mono, model: model, sampleRate: sampleRate);
