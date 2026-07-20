// lib/core/audio/transcription/rmvpe_model_store.dart
//
// NATIVE model provisioning for RMVPE — the `dart:io` half kept OUT of the
// web-safe `rmvpe.dart`. Downloads the MIT RMVPE ONNX (~361 MB — big; opt-in,
// native-only) and its mel filterbank asset (~0.27 MB) on demand and caches
// them, mirroring `crepe_model_store`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/rmvpe.dart';
import 'package:comet_beat/core/audio/transcription/rmvpe_mel.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show F0Estimator;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A loaded RMVPE bundle: the ONNX [model] and the parsed [mel] filterbank.
typedef RmvpeBundle = ({OnnxModel model, RmvpeMel mel});

/// Resolves + loads the MIT RMVPE model + mel asset. Override the cache location
/// with `COMET_RMVPE_DIR` (tests use this).
class RmvpeModelStore {
  RmvpeModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _base =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/';
  static const _modelUrl = '${_base}rmvpe.onnx';
  static const _melUrl = '${_base}rmvpe_mel.bin';

  RmvpeBundle? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_RMVPE_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/rmvpe.onnx');
  File melFile() => File('${cacheDir()}/rmvpe_mel.bin');

  /// Whether both files are already on disk (no network) — the readiness gate.
  bool isPresent() {
    final m = modelFile(), c = melFile();
    return m.existsSync() &&
        m.lengthSync() > 300000000 &&
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
      if (m == null || m.length < 300000000) return false;
      final c = await _get(_melUrl);
      if (c == null || c.length < 100000) return false;
      await modelFile().writeAsBytes(m);
      await melFile().writeAsBytes(c);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads (and memoises) the RMVPE bundle, downloading if needed. Throws a
  /// [StateError] if it can't be obtained.
  Future<RmvpeBundle> load() async {
    if (_cached != null) return _cached!;
    if (!await ensureFiles()) {
      throw StateError('RMVPE model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    final model = OnnxModel.fromBytes(modelFile().readAsBytesSync());
    final mel = RmvpeMel.fromBytes(melFile().readAsBytesSync());
    return _cached = (model: model, mel: mel);
  }

  /// Builds an [F0Estimator] backed by RMVPE for `transcribeAuto(f0: ...)` —
  /// a heavier, more robust alternative to CREPE. Loads (and memoises) the
  /// bundle. Native-only; the app wires this behind `!kIsWeb`.
  Future<F0Estimator> estimator() async {
    final b = await load();
    return (Float64List mono, int sampleRate) =>
        rmvpeF0(mono, model: b.model, mel: b.mel, sampleRate: sampleRate);
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-rmvpe';
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
