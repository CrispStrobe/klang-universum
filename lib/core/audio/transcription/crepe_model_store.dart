// lib/core/audio/transcription/crepe_model_store.dart
//
// NATIVE model provisioning for the CREPE F0 estimator — the `dart:io` half kept
// OUT of the web-safe `crepe.dart`. Mirrors BasicPitchModelStore exactly.
//
// TODO(model worker): set [_modelUrl] to a published MIT CREPE ONNX (e.g. the
// `crepe` / torchcrepe weights exported to ONNX — 'tiny' or 'small' is enough,
// input [1,1024] → output [1,360]). Until then ensureFile() returns null and the
// neural F0 path is simply unavailable (the router falls back to pYIN); nothing
// breaks. Ship the model's MIT LICENSE next to it, as Basic Pitch ships NOTICE.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Resolves + loads the MIT CREPE ONNX model. Override the cache location with
/// `COMET_CREPE_DIR` (tests use this).
class CrepeModelStore {
  CrepeModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  // TODO(model worker): the published CREPE ONNX URL. Empty = unavailable.
  static const _modelUrl = '';
  // Optional companion licence file URL (MIT).
  static const _licenseUrl = '';

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

  File modelFile() => File('${cacheDir()}/crepe.onnx');

  /// True when the model is already on disk (large enough), no network touched —
  /// the "is the neural F0 ready?" gate.
  bool isPresent() {
    final f = modelFile();
    return f.existsSync() && f.lengthSync() > 100000;
  }

  /// The cached model file, downloading it on first use. Returns null if absent
  /// and the download fails or no URL is configured yet — callers gate the model
  /// path skip-if-absent.
  Future<File?> ensureFile() async {
    final file = modelFile();
    if (file.existsSync() && file.lengthSync() > 100000) return file;
    if (_modelUrl.isEmpty) return null; // no URL configured yet
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < 100000) return null;
      await file.writeAsBytes(bytes);
      if (_licenseUrl.isNotEmpty) {
        final lic = await _get(_licenseUrl);
        if (lic != null) {
          await File('${cacheDir()}/LICENSE.crepe').writeAsBytes(lic);
        }
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
      throw StateError('CREPE model unavailable (no URL configured, or '
          'offline). Expected at ${modelFile().path}');
    }
    return _cached = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final c in resp) {
        chunks.addAll(c);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
