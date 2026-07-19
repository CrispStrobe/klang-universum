// Native provider: load the Basic Pitch ONNX model (download-on-demand) and wrap
// it as a NeuralTranscriber the router can inject. dart:io only — reached solely
// through neural_provider.dart's conditional import, so web never compiles it.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/basic_pitch.dart';
import 'package:comet_beat/core/audio/transcription/basic_pitch_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;

/// A transcriber backed by Basic Pitch, or null.
///
/// With [download] false, returns non-null only if the model is already cached
/// (no network touched). With [download] true, fetches it first. Returns null on
/// any failure so the caller can fall back to the monophonic chain.
Future<NeuralTranscriber?> loadNeuralTranscriber({
  bool download = false,
}) async {
  try {
    final store = BasicPitchModelStore();
    if (!download && !neuralModelPresent()) return null;
    final model =
        await store.load(); // downloads if missing (throws if it can't)
    return (Float64List mono, int sampleRate) async =>
        basicPitchTranscribe(mono, model: model, sampleRate: sampleRate);
  } on Object {
    return null;
  }
}

/// Whether the model is already on disk (a large-enough file), without touching
/// the network — the "is the HD engine ready?" gate for the UI.
bool neuralModelPresent() {
  try {
    final f = BasicPitchModelStore().modelFile();
    return f.existsSync() && f.lengthSync() > 100000;
  } on Object {
    return false;
  }
}
