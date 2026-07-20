// lib/core/audio/transcription/hubert_model_store.dart
//
// NATIVE model provisioning for the HuBERT / ContentVec content encoder — the
// `dart:io` half kept OUT of the web-safe `hubert.dart`. Downloads the MIT
// ContentVec ONNX (~290 MB, vec-256-layer-9 — dynamic-length, ORT-clean; the
// vec-768-layer-12 exports floating around are fixed-length / shape-broken) on
// demand and caches it, mirroring `piano_model_store`. ContentVec (fairseq
// HuBERT + the ContentVec finetune) is MIT — no licence gate (unlike the
// RVC/Beatrice *voice* weights, which are gated in their own stores).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/hubert.dart';
import 'package:comet_beat/core/audio/transcription/voice.dart'
    show ContentEncoder;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Resolves + loads the MIT HuBERT/ContentVec ONNX. Override the cache location
/// with `COMET_HUBERT_DIR` (tests use this).
class HubertModelStore {
  HubertModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _modelUrl =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/hubert-contentvec.onnx';
  static const _minBytes = 50000000; // guard partial downloads

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_HUBERT_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File modelFile() => File('${cacheDir()}/hubert-contentvec.onnx');

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
  Future<OnnxModel> load() async {
    if (_cached != null) return _cached!;
    final file = await ensureFile();
    if (file == null) {
      throw StateError('HuBERT/ContentVec model unavailable (offline?). '
          'Expected at ${modelFile().path}');
    }
    return _cached = OnnxModel.fromBytes(file.readAsBytesSync());
  }

  /// The [ContentEncoder] seam backed by this model.
  Future<ContentEncoder> encoder() async {
    final model = await load();
    return (Float64List mono, int sampleRate) =>
        hubertEncode(mono, model: model, sampleRate: sampleRate);
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-hubert';
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
