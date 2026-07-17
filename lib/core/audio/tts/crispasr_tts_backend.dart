// lib/core/audio/tts/crispasr_tts_backend.dart
//
// The NEURAL text-to-speech backend: CrispASR's ggml Kokoro model (82 M params,
// Apache-2.0, multilingual incl. de+en) via the pure-Dart `crispasr` FFI package
// over `libcrispasr`. It plugs into the TtsBackend seam (tts_service.dart) behind
// the platform `flutter_tts` fallback.
//
// Availability is conditional and safe: the native lib is `DynamicLibrary.open`ed
// and the Kokoro model is read ONLY when [isAvailable] passes (dylib loads + model
// file cached). Where they're absent — the common case until the model is
// downloaded and the lib is bundled per platform — [isAvailable] is false and
// TtsService uses the platform voice instead. Nothing here runs during
// pub-get / analyze / test (the FFI calls are reached only from [speak]).
//
// Synthesis (`session.synthesize` — a ~3 s blocking C call returning 24 kHz mono
// float32 PCM) runs in a background isolate so the UI never freezes; the PCM is
// wrapped as a WAV (synth.dart `wavBytes`) and handed to the injected [play]
// callback (AudioService in the app, a fake in tests).
//
// Model delivery is download-on-first-use + cache (see KokoroModelStore) — never
// bundled, keeping the app small. macOS is the first platform to bundle
// libcrispasr; other platforms fall back to flutter_tts until their lib ships.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:crispasr/crispasr.dart';

/// A self-contained synthesis request, shipped into the background isolate.
class KokoroSynthRequest {
  const KokoroSynthRequest({
    required this.libPath,
    required this.modelPath,
    required this.text,
    this.voicePath,
  });

  final String libPath;
  final String modelPath;
  final String text;
  final String? voicePath;
}

/// Synthesise [req.text] to PCM16 mono @ 24 kHz. Top-level + pure so `Isolate.run`
/// can ship it; opens its own dylib + session in the worker isolate. Returns null
/// on any failure (missing symbol, bad model, empty audio) so the caller can fall
/// back silently rather than surface an error to a child.
Int16List? synthesizeKokoroPcm16(KokoroSynthRequest req) {
  try {
    final session = CrispasrSession.open(
      req.modelPath,
      backend: 'kokoro',
      libPath: req.libPath,
    );
    try {
      final voice = req.voicePath;
      if (voice != null && voice.isNotEmpty) session.setVoice(voice);
      final pcm = session.synthesize(req.text);
      if (pcm.isEmpty) return null;
      final out = Int16List(pcm.length);
      for (var i = 0; i < pcm.length; i++) {
        final v = pcm[i];
        if (v.isNaN) return null; // a bad decode — bail to the fallback voice
        out[i] = (v * 32767.0).round().clamp(-32768, 32767);
      }
      return out;
    } finally {
      session.close();
    }
  } catch (_) {
    return null;
  }
}

/// Neural TtsBackend over CrispASR/Kokoro. Construct with a [store] (resolves the
/// dylib + cached model + per-locale voice) and a [play] sink for the finished
/// WAV; optionally a [stopPlayback] to interrupt it.
class CrispAsrTtsBackend implements TtsBackend {
  CrispAsrTtsBackend({
    required this.store,
    required this.play,
    this.stopPlayback,
    Future<Int16List?> Function(KokoroSynthRequest)? runSynthesis,
  }) : _runSynthesis = runSynthesis ??
            ((req) => Isolate.run(() => synthesizeKokoroPcm16(req)));

  final KokoroModelStore store;

  /// Plays the finished WAV (AudioService.playWavBytes in the app). Honouring the
  /// master sound switch is the sink's job (AudioService already gates on it).
  final Future<void> Function(Uint8List wav) play;

  /// Interrupts current playback (AudioService.stop) when narration is cancelled.
  final Future<void> Function()? stopPlayback;

  /// Seam for tests: run synthesis without a real isolate/native lib.
  final Future<Int16List?> Function(KokoroSynthRequest) _runSynthesis;

  /// True iff libcrispasr can be loaded AND the Kokoro model is cached — i.e.
  /// synthesis can actually run on this device right now.
  Future<bool> isAvailable() => store.isReady();

  @override
  Future<void> speak(String text, {required String langCode}) async {
    if (text.trim().isEmpty) return;
    final resolved = await store.resolve(langCode);
    if (resolved == null) {
      return; // not ready — TtsService will have fallen back
    }
    final pcm = await _runSynthesis(
      KokoroSynthRequest(
        libPath: resolved.libPath,
        modelPath: resolved.modelPath,
        voicePath: resolved.voicePath,
        text: text,
      ),
    );
    if (pcm == null || pcm.isEmpty) return;
    await play(wavBytes(pcm, sampleRate: 24000));
  }

  @override
  Future<void> stop() async {
    await stopPlayback?.call();
  }
}
