// lib/core/audio/transcription/harmony_model_store.dart
//
// NATIVE model provisioning for BTC chord recognition — the `dart:io` half kept
// OUT of the web-safe `harmony.dart`. Downloads the MIT BTC ONNX (~13 MB) and
// its CQT filterbank asset (~0.14 MB) on demand and caches them, mirroring
// `crepe_model_store`. Only native callers touch this.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/harmony_cqt.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A loaded BTC bundle: the ONNX [model] and the parsed CQT [cqt] filterbank.
typedef HarmonyBundle = ({OnnxModel model, CqtFilterBank cqt});

/// Resolves + loads the MIT BTC chord model + CQT asset. Override the cache
/// location with `COMET_HARMONY_DIR` (tests use this).
class HarmonyModelStore {
  HarmonyModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  // Hosted as release assets (not in the pub package), like crepe-tiny.
  static const _base =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/';
  static const _modelUrl = '${_base}btc-chord.onnx';
  static const _cqtUrl = '${_base}btc-cqt.bin';

  HarmonyBundle? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_HARMONY_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/btc-chord.onnx');
  File cqtFile() => File('${cacheDir()}/btc-cqt.bin');

  /// Whether both files are already on disk (no network) — the UI's readiness
  /// gate.
  bool isPresent() {
    final m = modelFile(), c = cqtFile();
    return m.existsSync() &&
        m.lengthSync() > 1000000 &&
        c.existsSync() &&
        c.lengthSync() > 10000;
  }

  /// Ensures both files exist, downloading on first use. Returns false if absent
  /// and the download fails (offline).
  Future<bool> ensureFiles() async {
    if (isPresent()) return true;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final m = await _get(_modelUrl);
      if (m == null || m.length < 1000000) return false;
      final c = await _get(_cqtUrl);
      if (c == null || c.length < 10000) return false;
      await modelFile().writeAsBytes(m);
      await cqtFile().writeAsBytes(c);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads (and memoises) the BTC bundle, downloading if needed. Throws a
  /// [StateError] if it can't be obtained.
  Future<HarmonyBundle> load() async {
    if (_cached != null) return _cached!;
    if (!await ensureFiles()) {
      throw StateError('BTC chord model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    final model = OnnxModel.fromBytes(modelFile().readAsBytesSync());
    final cqt = CqtFilterBank.fromBytes(cqtFile().readAsBytesSync());
    return _cached = (model: model, cqt: cqt);
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-harmony';
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
