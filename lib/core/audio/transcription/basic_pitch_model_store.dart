// lib/core/audio/transcription/basic_pitch_model_store.dart
//
// NATIVE model provisioning for the Basic Pitch transcriber — the `dart:io`
// half kept OUT of the web-safe `basic_pitch.dart`. Downloads the Apache-2.0
// ONNX model (`nmp.onnx`, ~230 KB) on demand and caches it, mirroring how the
// TTS/SF2 model stores fetch their assets. Only native callers touch this
// (the CLI, tests, and the app's transcription entry behind `!kIsWeb`); the
// pure transcriber stays importable on web.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Resolves + loads the Apache-2.0 Basic Pitch ONNX model. Override the cache
/// location with `COMET_BASICPITCH_DIR` (tests use this).
class BasicPitchModelStore {
  BasicPitchModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _modelUrl =
      'https://raw.githubusercontent.com/spotify/basic-pitch/main/'
      'basic_pitch/saved_models/icassp_2022/nmp.onnx';
  static const _noticeUrl =
      'https://raw.githubusercontent.com/spotify/basic-pitch/main/NOTICE';

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_BASICPITCH_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/nmp.onnx');

  /// The cached model file, downloading it (+ the Apache-2.0 NOTICE) on first
  /// use. Returns null if absent and the download fails (offline) — callers
  /// gate the model path skip-if-absent.
  Future<File?> ensureFile() async {
    final file = modelFile();
    if (file.existsSync() && file.lengthSync() > 100000) return file;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < 100000) return null;
      await file.writeAsBytes(bytes);
      final notice = await _get(_noticeUrl);
      if (notice != null) {
        await File('${cacheDir()}/NOTICE.basic_pitch').writeAsBytes(notice);
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Loads (and memoises) the model, downloading if needed. Throws a
  /// [StateError] if it can't be obtained.
  Future<OnnxModel> load() async {
    if (_cached != null) return _cached!;
    final file = await ensureFile();
    if (file == null) {
      throw StateError('Basic Pitch model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    // nmp.onnx is self-contained (no external data), so bytes → OnnxModel keeps
    // this off the `_io` model loader.
    return _cached = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final b = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        b.add(chunk);
      }
      return b.takeBytes();
    } finally {
      client.close();
    }
  }
}
