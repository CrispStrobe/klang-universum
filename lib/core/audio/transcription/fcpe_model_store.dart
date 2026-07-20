// lib/core/audio/transcription/fcpe_model_store.dart
//
// NATIVE model provisioning for FCPE — the `dart:io` half kept OUT of the
// web-safe `fcpe.dart`. Downloads the MIT FCPE ONNX (~43 MB) + its mel/cent
// asset (~0.27 MB) on demand and caches them, mirroring `rmvpe_model_store`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart'
    show autoPoolWorkers;
import 'package:comet_beat/core/audio/transcription/fcpe.dart';
import 'package:comet_beat/core/audio/transcription/fcpe_mel.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A loaded FCPE bundle: the ONNX [model] and the parsed [assets].
typedef FcpeBundle = ({OnnxModel model, FcpeAssets assets});

/// Resolves + loads the MIT FCPE model + mel/cent asset. Override the cache
/// location with `COMET_FCPE_DIR` (tests use this).
class FcpeModelStore {
  FcpeModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _base =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/';
  static const _modelUrl = '${_base}fcpe.onnx';
  static const _melUrl = '${_base}fcpe_mel.bin';

  FcpeBundle? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_FCPE_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/fcpe.onnx');
  File melFile() => File('${cacheDir()}/fcpe_mel.bin');

  /// Whether both files are already on disk (no network) — the readiness gate.
  bool isPresent() {
    final m = modelFile(), c = melFile();
    return m.existsSync() &&
        m.lengthSync() > 10000000 &&
        c.existsSync() &&
        c.lengthSync() > 100000;
  }

  /// Ensures both files exist, downloading on first use. Returns false if absent
  /// and the download fails (offline).
  Future<bool> ensureFiles() async {
    if (isPresent()) return true;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final m = await _get(_modelUrl);
      if (m == null || m.length < 10000000) return false;
      final c = await _get(_melUrl);
      if (c == null || c.length < 100000) return false;
      await modelFile().writeAsBytes(m);
      await melFile().writeAsBytes(c);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads (and memoises) the FCPE bundle, downloading if needed. Throws a
  /// [StateError] if it can't be obtained.
  Future<FcpeBundle> load() async {
    if (_cached != null) return _cached!;
    if (!await ensureFiles()) {
      throw StateError('FCPE model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    final model = OnnxModel.fromBytes(modelFile().readAsBytesSync());
    final assets = FcpeAssets.fromBytes(melFile().readAsBytesSync());
    return _cached = (model: model, assets: assets);
  }

  /// Builds an [F0Estimator] backed by FCPE — the FAST default F0. Sets up the
  /// isolate pool by default (FCPE is ~77% Conv → faster, bitwise-identical
  /// output); `COMET_FCPE_WORKERS=0` disables it. Native-only; wire behind
  /// `!kIsWeb`.
  Future<F0Estimator> estimator() async {
    final b = await load();
    final workers =
        int.tryParse(Platform.environment['COMET_FCPE_WORKERS'] ?? '') ??
            autoPoolWorkers();
    if (workers > 0) {
      await b.model.parallelize(workers: workers, poolConv: true);
      return (Float64List mono, int sampleRate) => fcpeF0Async(
            mono,
            model: b.model,
            assets: b.assets,
            sampleRate: sampleRate,
          );
    }
    return (Float64List mono, int sampleRate) =>
        fcpeF0(mono, model: b.model, assets: b.assets, sampleRate: sampleRate);
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-fcpe';
      var uri = Uri.parse(url);
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
