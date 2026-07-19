// lib/core/audio/transcription/crepe_model_store.dart
//
// NATIVE model provisioning for the CREPE F0 estimator — the `dart:io` half
// kept OUT of the web-safe `crepe.dart`. Downloads the MIT-licensed CREPE-tiny
// ONNX (~1.9 MB) on demand and caches it, mirroring `basic_pitch_model_store`
// and the TTS/SF2 stores. Only native callers touch this (the CLI, tests, and
// the app's transcription entry behind `!kIsWeb`); the pure estimator stays
// importable on web.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Resolves + loads the MIT CREPE-tiny ONNX model. Override the cache location
/// with `COMET_CREPE_DIR` (tests use this to point at a prebuilt model).
class CrepeModelStore {
  CrepeModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  // CREPE-tiny exported from torchcrepe (MIT), hosted as a release asset so it
  // is not bundled into the onnx_runtime_dart pub package.
  static const _modelUrl =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/crepe-tiny.onnx';

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_CREPE_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/crepe-tiny.onnx');

  /// The cached model file, downloading it on first use. Returns null if absent
  /// and the download fails (offline) — callers gate the model path
  /// skip-if-absent.
  Future<File?> ensureFile() async {
    final file = modelFile();
    if (file.existsSync() && file.lengthSync() > 500000) return file;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < 500000) return null;
      await file.writeAsBytes(bytes);
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
      throw StateError('CREPE model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    return _cached = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-crepe';
      var uri = Uri.parse(url);
      // Follow redirects (GitHub release assets 302 to a CDN).
      for (var hop = 0; hop < 5; hop++) {
        final req = await client.getUrl(uri);
        req.followRedirects = false;
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final b = BytesBuilder(copy: false);
          await for (final chunk in resp) {
            b.add(chunk);
          }
          return b.takeBytes();
        }
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (resp.isRedirect && loc != null) {
          uri = Uri.parse(loc);
          continue;
        }
        return null;
      }
      return null;
    } finally {
      client.close();
    }
  }
}

/// Builds an [F0Estimator] backed by CREPE, loading (and memoising) the model on
/// first call. Drops into the `transcribeAuto(f0: ...)` seam. Returns a closure
/// that resamples + runs CREPE per call. Native-only (uses [CrepeModelStore]);
/// the app wires this behind `!kIsWeb`.
Future<F0Estimator> crepeF0Estimator({CrepeModelStore? store}) async {
  final s = store ?? CrepeModelStore();
  final model = await s.load();
  return (Float64List mono, int sampleRate) =>
      crepeF0(mono, model: model, sampleRate: sampleRate);
}
