// lib/core/audio/tts/kokoro_model_store.dart
//
// Resolves (and, on first use, downloads + caches) the files the CrispASR/Kokoro
// neural TTS backend needs:
//   • libcrispasr — the native ggml engine, probed via the crispasr package's
//     per-platform candidate names (bundled per platform; macOS first). An
//     explicit override wins (COMET_CRISPASR_LIB, or the constructor) — used for
//     dev/verification against a locally-built dylib.
//   • kokoro-82m-f16.gguf — the acoustic model (~135 MB, Apache-2.0).
//   • kokoro-voice-<name>.gguf — a small per-locale voice pack (de → df_eva,
//     en → af_heart).
//
// Delivery is download-on-first-use into [cacheDir], then reused offline; the
// model is NEVER bundled, keeping the app small. Until the maintainer publishes
// the GGUFs and sets [modelBaseUrl], downloads are inert and [isReady] stays
// false, so TtsService simply uses the platform (flutter_tts) voice.

import 'dart:io';

import 'package:crispasr/crispasr.dart' show CrispASR;

/// The resolved absolute paths for one synthesis, or null when not ready.
class KokoroResolvedPaths {
  const KokoroResolvedPaths({
    required this.libPath,
    required this.modelPath,
    this.voicePath,
  });

  final String libPath;
  final String modelPath;
  final String? voicePath;
}

class KokoroModelStore {
  KokoroModelStore({
    required this.cacheDir,
    String? libPathOverride,
    String? modelPathOverride,
    Map<String, String>? voiceOverrides,
    this.modelBaseUrl,
    HttpClient Function()? httpClientFactory,
  })  : _libOverride =
            libPathOverride ?? Platform.environment['COMET_CRISPASR_LIB'],
        _modelOverride =
            modelPathOverride ?? Platform.environment['COMET_KOKORO_MODEL'],
        _voiceOverrides = voiceOverrides ?? const {},
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Directory that holds downloaded GGUFs (an app-support/cache dir in the app).
  final String cacheDir;

  /// Optional base URL for the published GGUFs, e.g. a HuggingFace resolve root.
  /// When null/empty, [ensureModel] is a no-op and neural TTS stays unavailable.
  final String? modelBaseUrl;

  final String? _libOverride;
  final String? _modelOverride;
  final Map<String, String> _voiceOverrides;
  final HttpClient Function() _httpClientFactory;

  static const modelFileName = 'kokoro-82m-f16.gguf';

  /// Per-locale voice pack file names (the app ships de + en).
  static const _voiceFiles = <String, String>{
    'de': 'kokoro-voice-df_eva.gguf',
    'en': 'kokoro-voice-af_heart.gguf',
  };

  String get _modelPath => _modelOverride ?? '$cacheDir/$modelFileName';

  String _voicePathFor(String lang) =>
      _voiceOverrides[lang] ??
      '$cacheDir/${_voiceFiles[lang] ?? _voiceFiles['en']}';

  /// The native lib path: an explicit override, else the crispasr package's
  /// per-platform default candidate (which the loader probes at open time).
  String get _libPath {
    if (_libOverride != null && _libOverride.isNotEmpty) return _libOverride;
    return CrispASR.defaultLibName();
  }

  /// True iff the native lib is loadable AND the model file is present — i.e.
  /// synthesis can run right now. Never throws.
  Future<bool> isReady() async {
    try {
      if (!_libLoadable()) return false;
      return File(_modelPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  bool _libLoadable() {
    try {
      final p = _libPath;
      // An absolute override must exist on disk; a bare candidate name is left
      // to the loader's search path (bundled frameworks) — assume loadable and
      // let the isolate's real open fail into the fallback if it isn't there.
      if (p.contains('/')) return File(p).existsSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolve the paths for [langCode] (`de`/`en`/…), downloading the model on
  /// first use if a [modelBaseUrl] is configured. Returns null when unavailable.
  Future<KokoroResolvedPaths?> resolve(String langCode) async {
    final lang = langCode.toLowerCase().split(RegExp('[-_]')).first;
    await ensureModel(lang);
    if (!await isReady()) return null;
    final voice = _voicePathFor(lang);
    return KokoroResolvedPaths(
      libPath: _libPath,
      modelPath: _modelPath,
      voicePath: File(voice).existsSync() ? voice : null,
    );
  }

  /// Download the model + [lang] voice into [cacheDir] if missing. No-op when no
  /// [modelBaseUrl] is set (the default until the GGUFs are published). Failures
  /// are swallowed — neural TTS just stays unavailable and the platform voice
  /// covers it.
  Future<void> ensureModel(String lang) async {
    final base = modelBaseUrl;
    if (base == null || base.isEmpty) return;
    try {
      await Directory(cacheDir).create(recursive: true);
      await _fetchIfMissing('$base/$modelFileName', _modelPath);
      final vf = _voiceFiles[lang] ?? _voiceFiles['en']!;
      await _fetchIfMissing('$base/$vf', '$cacheDir/$vf');
    } catch (_) {
      // leave whatever downloaded; isReady() decides usability
    }
  }

  Future<void> _fetchIfMissing(String url, String dest) async {
    final file = File(dest);
    if (file.existsSync() && file.lengthSync() > 0) return;
    final client = _httpClientFactory();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return;
      final tmp = File('$dest.part');
      await resp.pipe(tmp.openWrite());
      if (tmp.existsSync() && tmp.lengthSync() > 0) {
        await tmp.rename(dest);
      }
    } finally {
      client.close(force: true);
    }
  }
}
