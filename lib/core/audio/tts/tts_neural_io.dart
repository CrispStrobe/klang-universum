// lib/core/audio/tts/tts_neural_io.dart
//
// Native (dart:io + ffi) build of the neural TTS factory. Wires the CrispASR /
// Kokoro backend to a cache dir and returns it together with its readiness probe;
// TtsService only routes to it when that probe passes (native lib loadable +
// model cached), so this is inert until the model is downloaded and, off macOS,
// until libcrispasr is bundled for the platform.

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_tts_backend.dart';
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:comet_beat/core/services/tts_service.dart';

/// Where downloaded Kokoro GGUFs live. Mirrors the AECMOS convention
/// (`$HOME/.cache/...`); a proper app-support dir (path_provider) is a follow-up
/// for the mobile bundling pass.
String _cacheDir() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/comet_beat/tts';
}

/// The published-GGUF base URL (HuggingFace resolve root, once the maintainer
/// publishes the Kokoro + voice GGUFs — cf. the AECMOS `cstr/aecmos-onnx` repo).
/// Empty until then: downloads stay inert and neural TTS is simply unavailable,
/// so the platform voice covers narration.
const _modelBaseUrl = String.fromEnvironment('COMET_KOKORO_BASE_URL');

NeuralTts? createNeuralTts({
  required Future<void> Function(Uint8List wav) play,
  Future<void> Function()? stopPlayback,
}) {
  final store = KokoroModelStore(
    cacheDir: _cacheDir(),
    modelBaseUrl: _modelBaseUrl.isEmpty ? null : _modelBaseUrl,
  );
  final backend = CrispAsrTtsBackend(
    store: store,
    play: play,
    stopPlayback: stopPlayback,
  );
  return NeuralTts(backend, backend.isAvailable);
}
