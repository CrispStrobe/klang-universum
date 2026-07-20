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

import 'package:comet_beat/core/audio/transcription/contracts.dart';
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
      throw StateError(
        'CREPE model unavailable (offline?). '
        'Expected at ${modelFile().path}',
      );
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

/// How CREPE inference is executed — the knob that gates the sync vs
/// isolate-pool path. Resolve it from the environment with [CrepeRunConfig.fromEnv]
/// so the path can be A/B-benchmarked without recompiling:
///
///   COMET_CREPE_WORKERS   int, default 0  — 0 = single-threaded [crepeF0];
///                                            >0 = pool of N isolates + [crepeF0Async]
///   COMET_CREPE_POOLCONV  bool, default 1 — bring Conv into the pool (CREPE is
///                                            ~all Conv, so this is what matters;
///                                            the engine warns activation copying
///                                            may cancel the gain — measure)
///   COMET_CREPE_BATCH     int, default 512 — frames per inference batch
/// A sensible default isolate-pool worker count for offline neural inference —
/// CPU cores minus a couple (the UI isolate + headroom), capped at 6, and 0 on
/// ≤2-core devices (where the pool's setup cost outweighs the gain).
int autoPoolWorkers() {
  final n = Platform.numberOfProcessors - 2;
  return n < 0 ? 0 : (n > 6 ? 6 : n);
}

class CrepeRunConfig {
  const CrepeRunConfig({
    this.workers = 0,
    this.poolConv = true,
    this.batchFrames = 512,
  });

  final int workers;
  final bool poolConv;
  final int batchFrames;

  /// True when the isolate-pool path should be used.
  bool get parallel => workers > 0;

  factory CrepeRunConfig.fromEnv([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    int pInt(String k, int d) => int.tryParse(e[k] ?? '') ?? d;
    bool pBool(String k, bool d) {
      final v = e[k]?.trim().toLowerCase();
      if (v == null || v.isEmpty) return d;
      return v == '1' || v == 'true' || v == 'yes' || v == 'on';
    }

    return CrepeRunConfig(
      // Default the isolate pool ON — measured ~2.6× (0.6×→1.7× realtime) on
      // this Conv-heavy model, bitwise-identical output. `COMET_CREPE_WORKERS=0`
      // disables it. Auto count leaves headroom for the UI isolate + small cores.
      workers: pInt('COMET_CREPE_WORKERS', autoPoolWorkers()),
      poolConv: pBool('COMET_CREPE_POOLCONV', true),
      batchFrames: pInt('COMET_CREPE_BATCH', 512),
    );
  }

  @override
  String toString() => 'CrepeRunConfig(workers: $workers, poolConv: $poolConv, '
      'batchFrames: $batchFrames)';
}

/// Runs CREPE over [mono] honouring [config]: sets up the isolate pool when
/// `config.parallel`, then dispatches to [crepeF0Async] (pooled) or [crepeF0]
/// (single-threaded). Native-only. `parallelize` is invoked once per call here,
/// so prefer building an estimator ([crepeF0Estimator]) for repeated use.
Future<PitchTrack> crepeRun(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = 44100,
  CrepeRunConfig config = const CrepeRunConfig(),
  double fmin = 50,
  double fmax = 2006,
}) async {
  if (config.parallel) {
    await model.parallelize(workers: config.workers, poolConv: config.poolConv);
    return crepeF0Async(
      mono,
      model: model,
      sampleRate: sampleRate,
      fmin: fmin,
      fmax: fmax,
      batchFrames: config.batchFrames,
    );
  }
  return crepeF0(
    mono,
    model: model,
    sampleRate: sampleRate,
    fmin: fmin,
    fmax: fmax,
    batchFrames: config.batchFrames,
  );
}

/// Builds an [F0Estimator] backed by CREPE, loading (and memoising) the model on
/// first call and setting up the isolate pool ONCE if [config] (default: from
/// env) selects the parallel path. Drops into the `transcribeAuto(f0: ...)` seam.
/// Native-only (uses [CrepeModelStore]); the app wires this behind `!kIsWeb`.
Future<F0Estimator> crepeF0Estimator({
  CrepeModelStore? store,
  CrepeRunConfig? config,
}) async {
  final s = store ?? CrepeModelStore();
  final model = await s.load();
  final cfg = config ?? CrepeRunConfig.fromEnv();
  if (cfg.parallel) {
    await model.parallelize(workers: cfg.workers, poolConv: cfg.poolConv);
    return (Float64List mono, int sampleRate) => crepeF0Async(
          mono,
          model: model,
          sampleRate: sampleRate,
          batchFrames: cfg.batchFrames,
        );
  }
  return (Float64List mono, int sampleRate) => crepeF0(
        mono,
        model: model,
        sampleRate: sampleRate,
        batchFrames: cfg.batchFrames,
      );
}
