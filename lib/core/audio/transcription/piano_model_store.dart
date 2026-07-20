// lib/core/audio/transcription/piano_model_store.dart
//
// NATIVE model provisioning for the Kong piano-transcription model — the
// `dart:io` half kept OUT of the web-safe `piano.dart`. Downloads the MIT
// ByteDance/Kong note ONNX (~99 MB) on demand and caches it, mirroring
// `separate_umx_model_store` / `rmvpe_model_store`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/piano.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// A loaded Kong piano model.
typedef OnnxPianoModel = ({OnnxModel model});

/// Resolves + loads the MIT Kong piano ONNX. Override the cache location with
/// `COMET_PIANO_DIR` (tests use this).
class PianoModelStore {
  PianoModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _modelUrl =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/piano.onnx';
  static const _minBytes = 50000000; // ~99 MB; guard partial downloads

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_PIANO_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/piano.onnx');

  /// Whether the model is already on disk (no network) — the readiness gate.
  bool isPresent() {
    final f = modelFile();
    return f.existsSync() && f.lengthSync() > _minBytes;
  }

  /// The cached model file, downloading it on first use. Returns null if absent
  /// and the download fails (offline).
  Future<File?> ensureFile() async {
    final file = modelFile();
    if (isPresent()) return file;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get(_modelUrl);
      if (bytes == null || bytes.length < _minBytes) return null;
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Loads (and memoises) the model, downloading if needed. Throws a
  /// [StateError] if it can't be obtained.
  Future<OnnxPianoModel> load() async {
    if (_cached != null) return (model: _cached!);
    final file = await ensureFile();
    if (file == null) {
      throw StateError('Kong piano model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    _cached = OnnxModel.fromBytes(file.readAsBytesSync());
    return (model: _cached!);
  }

  /// The route.dart [NeuralTranscriber] backed by this model.
  Future<NeuralTranscriber> transcriber() async =>
      pianoTranscriber((await load()).model);

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-piano';
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
