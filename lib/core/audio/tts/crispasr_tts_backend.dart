// lib/core/audio/tts/crispasr_tts_backend.dart
//
// The NEURAL text-to-speech backend: CrispASR's ggml Kokoro model (82 M params,
// Apache-2.0, multilingual incl. de+en) via the pure-Dart `crispasr` FFI package
// over `libcrispasr`. Plugs into the TtsBackend seam (tts_service.dart) behind the
// platform `flutter_tts` fallback.
//
// Model files come from CrispASR's own registry + downloader (KokoroModelStore) —
// the same `-m auto` mechanism the CLI and CrisperWeaver use; nothing is bundled.
// Downloading is CONSENT-GATED: playback ([speak]) never downloads (it uses the
// model only if already cached, else stays silent so TtsService falls back);
// [download] is the explicit opt-in (a settings action, mirroring CrisperWeaver's
// model manager).
//
// Everything that touches the native lib runs in a background isolate ([_run]) so
// the UI never blocks on the ~3 s synthesis or a first-time model download. The
// PCM (24 kHz float32) is wrapped as a WAV (synth.dart `wavBytes`) and handed to
// the injected [play] sink (AudioService in the app, a fake in tests).

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show wavBytes;
import 'package:comet_beat/core/audio/tts/kokoro_model_store.dart';
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:crispasr/crispasr.dart';

/// A self-contained job shipped into the worker isolate: resolve (and optionally
/// download) the Kokoro model + [lang] voice, then — if [text] is non-null —
/// synthesise it. Plain fields only, so it's sendable.
class KokoroJob {
  const KokoroJob({
    required this.libPath,
    required this.lang,
    this.cacheDirOverride,
    this.text,
    this.download = false,
  });

  final String libPath;
  final String lang;
  final String? cacheDirOverride;
  final String? text;

  /// When false, missing files are NOT fetched — the job resolves only what's
  /// already cached (so playback never triggers a surprise download).
  final bool download;
}

/// Resolve a registry file to a local path — cached if present, downloaded via
/// CrispASR's own C downloader when [download] is set, else null.
String? _ensureFile(
  DynamicLibrary lib,
  String dir,
  String filename,
  String url,
  String? cacheDirOverride,
  bool download,
) {
  final path = '$dir/$filename';
  final f = File(path);
  if (f.existsSync() && f.lengthSync() > 0) return path;
  if (!download || url.isEmpty) return null;
  return cacheEnsureFile(
    filename,
    url,
    quiet: true,
    cacheDirOverride: cacheDirOverride,
    lib: lib,
  );
}

/// The published URL for a voice pack: the registry if it has it, else derived
/// from the af_heart entry (all voices share the cstr/kokoro-voices-GGUF repo).
String _voiceUrl(DynamicLibrary lib, String voiceFile) {
  final direct = registryLookupByFilename(voiceFile, lib: lib);
  if (direct != null) return direct.url;
  final af = registryLookupByFilename('kokoro-voice-af_heart.gguf', lib: lib);
  if (af != null) {
    return af.url.replaceFirst('kokoro-voice-af_heart.gguf', voiceFile);
  }
  return '';
}

/// Worker-isolate entry: resolve/download + synthesise. Returns PCM16 mono @
/// 24 kHz, an empty list for a download-only warmup, or null on any failure.
Int16List? runKokoroJob(KokoroJob job) {
  try {
    final lib = DynamicLibrary.open(job.libPath);
    final dir = cacheDir(override: job.cacheDirOverride, lib: lib);
    if (dir == null) return null;

    final model = registryLookup(KokoroModelStore.kokoroBackend, lib: lib);
    if (model == null) return null;
    final modelPath = _ensureFile(
      lib,
      dir,
      model.filename,
      model.url,
      job.cacheDirOverride,
      job.download,
    );
    if (modelPath == null) return null;

    // Download-only warmup: model is present, we're done.
    if (job.text == null || job.text!.trim().isEmpty) return Int16List(0);

    final voiceFile = KokoroModelStore.voiceFileFor(job.lang);
    final voicePath = _ensureFile(
      lib,
      dir,
      voiceFile,
      _voiceUrl(lib, voiceFile),
      job.cacheDirOverride,
      job.download,
    );

    return synthesizeKokoroPcm16(
      KokoroSynthRequest(
        libPath: job.libPath,
        modelPath: modelPath,
        voicePath: voicePath,
        text: job.text!,
      ),
    );
  } catch (_) {
    return null;
  }
}

/// A resolved-paths synthesis request (no registry/download — explicit paths).
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

/// Low-level synthesis from explicit paths → PCM16 mono @ 24 kHz. Pure + top-level
/// so it runs in the worker isolate; null on failure or a NaN/empty decode.
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
        if (v.isNaN) return null; // bad decode — bail to the fallback voice
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

/// Neural TtsBackend over CrispASR/Kokoro.
class CrispAsrTtsBackend implements TtsBackend {
  CrispAsrTtsBackend({
    required this.store,
    required this.play,
    this.stopPlayback,
    Future<Int16List?> Function(KokoroJob)? runJob,
  }) : _run = runJob ?? ((j) => Isolate.run(() => runKokoroJob(j)));

  final KokoroModelStore store;

  /// Plays the finished WAV (AudioService.playWavBytes). The sink honours the
  /// master sound switch.
  final Future<void> Function(Uint8List wav) play;

  /// Interrupts current playback when narration is cancelled.
  final Future<void> Function()? stopPlayback;

  final Future<Int16List?> Function(KokoroJob) _run;

  /// True iff synthesis can run right now (native lib loadable + model cached).
  Future<bool> isAvailable() => store.isReady();

  /// True iff the HD voice is possible on this platform (native lib loadable);
  /// the model may still need downloading via [download].
  Future<bool> supported() => store.supported();

  static String _lang(String langCode) =>
      langCode.toLowerCase().split(RegExp('[-_]')).first;

  @override
  Future<void> speak(String text, {required String langCode}) async {
    if (text.trim().isEmpty) return;
    // download defaults to false: playback never fetches — TtsService only routes
    // here when the model is already cached (isAvailable).
    final pcm = await _run(
      KokoroJob(
        libPath: store.libPath(),
        cacheDirOverride: store.cacheDirOverride,
        lang: _lang(langCode),
        text: text,
      ),
    );
    if (pcm == null || pcm.isEmpty) return;
    await play(wavBytes(pcm, sampleRate: 24000));
  }

  /// Explicit opt-in download of the model + [langCode] voice (a settings
  /// action, mirroring CrisperWeaver's model manager). Returns true once ready.
  Future<bool> download(String langCode) async {
    await _run(
      KokoroJob(
        libPath: store.libPath(),
        cacheDirOverride: store.cacheDirOverride,
        lang: _lang(langCode),
        download: true,
      ),
    );
    return store.isReady();
  }

  @override
  Future<void> stop() async {
    await stopPlayback?.call();
  }
}
