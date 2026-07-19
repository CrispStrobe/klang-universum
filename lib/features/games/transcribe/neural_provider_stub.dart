// Web / no-dart:io fallback: there is no neural engine, so the router uses the
// pure-Dart monophonic chain. Signature must match neural_provider_io.dart.

import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;

/// Always null on web — no ONNX. [download] is accepted for a matching signature.
Future<NeuralTranscriber?> loadNeuralTranscriber({
  bool download = false,
}) async =>
    null;

/// The model is never present on web.
bool neuralModelPresent() => false;
