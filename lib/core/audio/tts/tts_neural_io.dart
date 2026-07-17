// lib/core/audio/tts/tts_neural_io.dart
//
// Native (dart:io + ffi) build of the neural TTS factory. Wires the CrispASR /
// Kokoro backend and returns it with its readiness probe; TtsService routes to it
// only when the probe passes (native lib loadable + model cached). Model files are
// resolved + downloaded through CrispASR's own registry + cache (see
// KokoroModelStore) — nothing to configure or publish.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tts/crispasr_tts_backend.dart';
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:comet_beat/core/services/tts_service.dart';

NeuralTts? createNeuralTts({
  required Future<void> Function(Uint8List wav) play,
  Future<void> Function()? stopPlayback,
}) {
  // cacheDirOverride: null → CrispASR's own cache dir (~/.cache/crispasr). A mobile
  // sandbox dir (path_provider) can be passed here in the platform-bundling pass.
  final store = KokoroModelStore();
  final backend = CrispAsrTtsBackend(
    store: store,
    play: play,
    stopPlayback: stopPlayback,
  );
  return NeuralTts(
    backend: backend,
    ready: backend.isAvailable,
    supported: backend.supported,
    download: backend.download,
  );
}
