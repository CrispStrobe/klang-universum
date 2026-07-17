// lib/core/audio/tts/kokoro_model_store.dart
//
// Resolves the CrispASR/Kokoro model + per-locale voice using CrispASR's OWN
// model registry and downloader — the same mechanism the `crispasr` CLI (`-m
// auto`) and CrisperWeaver's model manager use. No hand-rolled URLs:
//   • registryLookup('kokoro')          → the canonical model GGUF + its published
//                                          HuggingFace URL (cstr/kokoro-82m-GGUF).
//   • cacheEnsureFile(filename, url)     → CrispASR's C-side downloader; caches
//                                          into its cache dir and returns the path
//                                          (or the cached path if already there).
//   • cacheDir()                          → CrispASR's cache dir (~/.cache/crispasr
//                                          on POSIX), or an app-sandbox override.
//
// This holder just answers "is the model already downloaded?" ([isReady]) and
// carries the config the synthesis isolate needs; the actual registry/cache/FFI
// calls happen in the worker isolate (crispasr_tts_backend.dart), off the UI
// thread. Downloading is consent-gated there — never triggered by playback.

import 'dart:ffi';
import 'dart:io';

import 'package:crispasr/crispasr.dart';

class KokoroModelStore {
  KokoroModelStore({this.cacheDirOverride, String? libPathOverride})
      : _libOverride =
            libPathOverride ?? Platform.environment['COMET_CRISPASR_LIB'];

  /// App-sandbox cache dir; null uses CrispASR's default (`~/.cache/crispasr`).
  final String? cacheDirOverride;
  final String? _libOverride;

  static const kokoroBackend = 'kokoro';

  /// The registered model filename, if the registry can't be reached (no lib).
  static const _fallbackModelFile = 'kokoro-82m-q8_0.gguf';

  /// Per-locale voice pack (both live in cstr/kokoro-voices-GGUF). de →
  /// df_victoria (registry-registered German voice), en → af_heart.
  static const _voiceForLang = <String, String>{
    'de': 'kokoro-voice-df_victoria.gguf',
    'en': 'kokoro-voice-af_heart.gguf',
  };

  static String voiceFileFor(String lang) =>
      _voiceForLang[lang] ?? _voiceForLang['en']!;

  /// Absolute path of the native lib (override wins; else the crispasr package's
  /// per-platform default candidate, resolved by the loader).
  String libPath() => (_libOverride != null && _libOverride.isNotEmpty)
      ? _libOverride
      : CrispASR.defaultLibName();

  DynamicLibrary? _tryOpenLib() {
    try {
      return DynamicLibrary.open(libPath());
    } catch (_) {
      return null;
    }
  }

  /// True iff the native lib loads AND the model GGUF is already cached — i.e.
  /// synthesis can run now without a download. False ⇒ TtsService uses the
  /// platform voice (and a UI action can call the backend's `download`).
  Future<bool> isReady() async {
    final lib = _tryOpenLib();
    if (lib == null) return false;
    try {
      final dir = cacheDir(override: cacheDirOverride, lib: lib);
      if (dir == null) return false;
      final model = registryLookup(kokoroBackend, lib: lib)?.filename ??
          _fallbackModelFile;
      final f = File('$dir/$model');
      return f.existsSync() && f.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }
}
