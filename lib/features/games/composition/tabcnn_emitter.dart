// The pure-Dart audio→tab emission provider: turns a guitar recording into the
// [TabEmissionFrames] that tab_emission_decoder.dart's Viterbi consumes, by
// running the GuitarSet-trained TabCNN (published by onnx_runtime_dart) on a raw
// CQT front-end. It fills the [TabEmissionModel] seam; the app/CLI hands the
// result to decodeTabEmissions() → tab.
//
// The model + its 192-bin CQT filterbank blob ship as onnx_runtime_dart
// `models-v1` release assets (TabCnnModelStore downloads + caches them, like
// crepe_model_store). Native-only (dart:io); the app wires this behind !kIsWeb.
//
// ⚠ TabCNN was trained on RAW CQT magnitude — NOT the log-magnitude BTC uses. So
// the front-end calls btcCqtFeature(logMag: false); feeding the BTC log feature
// would be a silent scale error (the model would read log where it learnt
// linear). This is the one non-obvious detail; everything else is a wire-up.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/harmony_cqt.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show Fretting;
import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// TabCNN's CQT sample rate (the model was trained at 22.05 kHz).
const int kTabCnnSampleRate = 22050;

/// TabCNN's context window: 9 CQT frames (±4 around the target) per prediction.
const int kTabCnnContext = 9;

/// The model's tensor names (exported by onnx_runtime_dart's tabcnn pipeline).
const String _inName = 'input';
const String _outName = 'output';

/// Runs a batch of [nWindows] context windows (flat `[nWindows·192·9]`, the
/// model's `[N,192,9,1]` input) through the emitter, returning the flat
/// `[nWindows·6·21]` log-probs. The ONLY model-runtime coupling — inject a fake
/// for tests, or the real onnx_runtime_dart runner via [TabCnnEmitter].
typedef TabWindowRunner = Float32List Function(
  Float32List windows,
  int nWindows,
);

/// Peak-normalises [x] to max |amplitude| = 1 (librosa.util.normalize, norm=inf);
/// silence is left unchanged. Matches TabCNN's preprocessing (before resample).
Float64List peakNormalize(Float64List x) {
  var peak = 0.0;
  for (final v in x) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  if (peak < 1e-8) return x;
  final out = Float64List(x.length);
  final scale = 1.0 / peak;
  for (var i = 0; i < x.length; i++) {
    out[i] = x[i] * scale;
  }
  return out;
}

/// Builds the model's input windows from a row-major `[nFrames × nBins]` CQT
/// [feat]: for each frame `t` a centred, zero-padded 9-frame context, laid out
/// bin-major then context (`window[bin·9 + ctx]`) to match the exported
/// `[N,192,9,1]` tensor. Returns flat `[nFrames · nBins · 9]`.
Float32List tabContextWindows(Float32List feat, int nFrames, int nBins) {
  const win = kTabCnnContext;
  const half = win ~/ 2; // 4
  final out = Float32List(nFrames * nBins * win);
  for (var t = 0; t < nFrames; t++) {
    for (var ctx = 0; ctx < win; ctx++) {
      final src = t - half + ctx;
      if (src < 0 || src >= nFrames) continue; // zero-pad the edges
      final srcBase = src * nBins;
      final dstBase = t * nBins * win;
      for (var bin = 0; bin < nBins; bin++) {
        out[dstBase + bin * win + ctx] = feat[srcBase + bin];
      }
    }
  }
  return out;
}

/// The core emit: [mono] → [TabEmissionFrames] of `[T,6,21]` log-probs, via the
/// raw-magnitude CQT front-end + [run] (batched by [batch] windows). Web-safe
/// given a preloaded [cqt] + a [run]; [TabCnnEmitter] supplies the real runner.
TabEmissionFrames tabcnnEmitWithRunner(
  Float64List mono, {
  required CqtFilterBank cqt,
  required TabWindowRunner run,
  int sampleRate = 44100,
  int batch = 256,
}) {
  final hop = cqt.hop / kTabCnnSampleRate;
  final empty = TabEmissionFrames(
    nFrames: 0,
    hopSeconds: hop,
    logProbs: Float64List(0),
  );
  if (mono.isEmpty) return empty; // no recording → no tab (CQT would emit 1)

  final normed = peakNormalize(mono);
  final audio = sampleRate == kTabCnnSampleRate
      ? normed
      : resampleLinear(normed, sampleRate / kTabCnnSampleRate);
  // Raw magnitude (logMag:false) — TabCNN's training feature.
  final (feat, nFrames) = btcCqtFeature(cqt, audio, logMag: false);
  final nBins = cqt.nBins;
  if (nFrames == 0) return empty;

  final windows = tabContextWindows(feat, nFrames, nBins);
  const perWin = kTabStrings * kTabClasses; // 126
  final out = Float64List(nFrames * perWin);
  final winLen = nBins * kTabCnnContext;
  for (var start = 0; start < nFrames; start += batch) {
    final n = math.min(batch, nFrames - start);
    final chunk = Float32List.sublistView(
      windows,
      start * winLen,
      (start + n) * winLen,
    );
    final lp = run(Float32List.fromList(chunk), n);
    for (var i = 0; i < n * perWin; i++) {
      out[start * perWin + i] = lp[i];
    }
  }
  return TabEmissionFrames(nFrames: nFrames, hopSeconds: hop, logProbs: out);
}

/// [TabEmissionModel] backed by the onnx_runtime_dart TabCNN + its CQT blob.
class TabCnnEmitter implements TabEmissionModel {
  TabCnnEmitter({required this.model, required this.cqt});

  final OnnxModel model;
  final CqtFilterBank cqt;

  @override
  TabEmissionFrames? emit(Float64List monoAudio, int sampleRate) =>
      tabcnnEmitWithRunner(
        monoAudio,
        cqt: cqt,
        sampleRate: sampleRate,
        run: (windows, nWindows) {
          final shape = [nWindows, cqt.nBins, kTabCnnContext, 1];
          final r = model.run(
            {_inName: Tensor.float(windows, shape)},
            const [_outName],
          )[_outName]!;
          return r.f ?? r.asFloatList();
        },
      );
}

/// End-to-end audio→tab: load the model (via [store], default [TabCnnModelStore]),
/// emit `[T,6,21]` log-probs, and decode them to one [Fretting] per frame. Null
/// when the model is unavailable (offline / web) so callers fall back. The caller
/// quantises the per-frame frettings (× the emitter's frame hop) into notes.
Future<List<Fretting>?> audioToTab(
  Float64List mono,
  int sampleRate, {
  TabCnnModelStore? store,
}) async {
  final loaded = await (store ?? TabCnnModelStore()).load();
  if (loaded == null) return null;
  final emitter = TabCnnEmitter(model: loaded.model, cqt: loaded.cqt);
  final frames = emitter.emit(mono, sampleRate);
  if (frames == null || frames.nFrames == 0) return null;
  return decodeTabEmissions(frames);
}

/// Resolves + caches the TabCNN ONNX model and its CQT filterbank blob from the
/// onnx_runtime_dart `models-v1` release. Override the cache dir with
/// `COMET_TABCNN_DIR` (tests point it at a prebuilt pair). Mirrors
/// crepe_model_store — native-only, null/throw on offline.
class TabCnnModelStore {
  TabCnnModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _base =
      'https://github.com/CrispStrobe/onnx_runtime_dart/releases/download/'
      'models-v1/';

  ({OnnxModel model, CqtFilterBank cqt})? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_TABCNN_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  File _file(String name) => File('${cacheDir()}/$name');

  Future<File?> _ensure(String name, int minBytes) async {
    final file = _file(name);
    if (file.existsSync() && file.lengthSync() > minBytes) return file;
    try {
      Directory(cacheDir()).createSync(recursive: true);
      final bytes = await _get('$_base$name');
      if (bytes == null || bytes.length < minBytes) return null;
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Loads (and memoises) the model + CQT blob, downloading on first use.
  /// Returns null if either can't be obtained (offline) so callers gate the
  /// audio-tab path skip-if-absent.
  Future<({OnnxModel model, CqtFilterBank cqt})?> load() async {
    if (_cached != null) return _cached;
    final onnx = await _ensure('tabcnn.onnx', 500000);
    final blob = await _ensure('tabcnn-cqt.bin', 100000);
    if (onnx == null || blob == null) return null;
    return _cached = (
      model: OnnxModel.fromBytes(onnx.readAsBytesSync()),
      cqt: CqtFilterBank.fromBytes(blob.readAsBytesSync()),
    );
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-tabcnn';
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
