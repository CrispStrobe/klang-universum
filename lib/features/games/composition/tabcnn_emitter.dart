// The pure-Dart audio→tab emission provider: turns a guitar recording into the
// [TabEmissionFrames] that tab_emission_decoder.dart's Viterbi consumes, by
// running TabCNN (published by onnx_runtime_dart on HF `cstr/tabcnn-onnx`) on a
// CQT front-end. It fills the [TabEmissionModel] seam; the app/CLI hands the
// result to decodeTabEmissions() → tab.
//
// TWO published models share the SAME [N,192,9,1]→[N,6,21] contract (class 0 =
// silent, class k = fret k−1 — gpfx is class-remapped at export to match), but
// need DIFFERENT front-end normalization of the SAME raw CQT magnitude:
//   • gpfx (GuitarProFX-augmented, DEFAULT) — robust on real/electric tones
//     (EGSet12 F1 ≈ 0.77): per-clip amplitude→dB then min-max to [0,1].
//   • vanilla (GuitarSet) — clean/acoustic (~0.45 zero-shot): raw magnitude.
// Both start from btcCqtFeature(logMag: false) — the raw |CQT|/√length; NOT the
// log-magnitude BTC uses (feeding BTC's log would be a silent scale error). The
// per-variant normalization ([gpfxNormalize] vs none) is the one subtle detail.
//
// The models + shared 192-bin CQT blob download + cache via TabCnnModelStore
// (like crepe_model_store). Native-only (dart:io); the app wires it behind !kIsWeb.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_tab.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart'
    show Backend;
import 'package:comet_beat/core/audio/transcription/harmony_cqt.dart';
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show Fretting;
import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Which TabCNN weights an emitter runs — they need different feature scaling.
enum TabCnnVariant { gpfx, vanilla }

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

/// The GuitarProFX front-end normalization applied to the raw-magnitude CQT
/// [feat] (row-major, in place returns a copy): per-clip `amplitude_to_db`
/// (librosa, ref = max, top_db = 80 → dB in [−80, 0]) then min-max to [0,1] over
/// the WHOLE feature matrix. Matches the gpfx training preprocessing.
Float32List gpfxNormalize(Float32List feat) {
  if (feat.isEmpty) return feat;
  const amin = 1e-10; // power-domain floor ((1e-5)² on amplitude)
  var maxMag = 0.0;
  for (final v in feat) {
    if (v > maxMag) maxMag = v;
  }
  final refDb = 10 * _log10(math.max(amin, maxMag * maxMag));
  final db = Float64List(feat.length);
  var dbMax = double.negativeInfinity;
  for (var i = 0; i < feat.length; i++) {
    final v = feat[i];
    final d = 10 * _log10(math.max(amin, v * v)) - refDb;
    db[i] = d;
    if (d > dbMax) dbMax = d;
  }
  final floor = dbMax - 80.0; // top_db
  var dbMin = double.infinity;
  for (var i = 0; i < db.length; i++) {
    if (db[i] < floor) db[i] = floor;
    if (db[i] < dbMin) dbMin = db[i];
  }
  final range = dbMax - dbMin + 1e-9;
  final out = Float32List(feat.length);
  for (var i = 0; i < db.length; i++) {
    out[i] = (db[i] - dbMin) / range;
  }
  return out;
}

double _log10(double x) => math.log(x) / math.ln10;

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
  TabCnnVariant variant = TabCnnVariant.gpfx,
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
  // Raw |CQT| magnitude (logMag:false); gpfx then re-scales it to dB→[0,1].
  final (raw, nFrames) = btcCqtFeature(cqt, audio, logMag: false);
  final feat = variant == TabCnnVariant.gpfx ? gpfxNormalize(raw) : raw;
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

/// [TabEmissionModel] backed by a TabCNN [variant] + its CQT blob.
class TabCnnEmitter implements TabEmissionModel {
  TabCnnEmitter({
    required this.model,
    required this.cqt,
    this.variant = TabCnnVariant.gpfx,
  });

  final OnnxModel model;
  final CqtFilterBank cqt;
  final TabCnnVariant variant;

  @override
  void dispose() {} // pure-Dart onnx — nothing native to free

  @override
  TabEmissionFrames? emit(Float64List monoAudio, int sampleRate) =>
      tabcnnEmitWithRunner(
        monoAudio,
        cqt: cqt,
        variant: variant,
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

/// End-to-end audio→tab, decoded to one [Fretting] per frame. The backend is
/// chosen by [prefer] (mirrors the transcription pipeline's per-step routing):
///   • [Backend.auto] (default) — native CrispASR ggml first (faster,
///     GPU-capable), falling back to the pure-Dart-onnx [TabCnnEmitter].
///   • [Backend.crispasr] — native ggml ONLY; null if it isn't present.
///   • [Backend.onnx] (or [Backend.pureDart]) — the onnx emitter only, skipping
///     native (works on web).
/// Null when the chosen path is unavailable (offline / web). A test [store]
/// forces the onnx path inline. The caller quantises the frettings (× the
/// emitter's frame hop) into notes.
Future<List<Fretting>?> audioToTab(
  Float64List mono,
  int sampleRate, {
  TabCnnModelStore? store,
  Backend prefer = Backend.auto,
}) async {
  // Native ggml unless a test store pins onnx, or the caller pinned onnx.
  final tryNative =
      store == null && (prefer == Backend.auto || prefer == Backend.crispasr);
  if (tryNative) {
    final native = await crispasrFfiTab(download: true);
    if (native != null) {
      try {
        final frames = native.emit(mono, sampleRate);
        if (frames != null && frames.nFrames > 0) {
          return decodeTabEmissions(frames);
        }
      } finally {
        native.dispose();
      }
    }
    // A pinned-native request doesn't silently fall through to onnx.
    if (prefer == Backend.crispasr) return null;
  }
  final loaded = await (store ?? TabCnnModelStore()).load();
  if (loaded == null) return null;
  final emitter = TabCnnEmitter(
    model: loaded.model,
    cqt: loaded.cqt,
    variant: loaded.variant,
  );
  final frames = emitter.emit(mono, sampleRate);
  if (frames == null || frames.nFrames == 0) return null;
  return decodeTabEmissions(frames);
}

/// Resolves + caches the TabCNN ONNX model + its CQT blob from HF
/// `cstr/tabcnn-onnx`. Prefers the robust **gpfx** variant (`prefer`), falling
/// back to vanilla when gpfx can't be fetched. Override the cache dir with
/// `COMET_TABCNN_DIR` (tests point it at a prebuilt pair). Mirrors
/// crepe_model_store — native-only, null on offline.
class TabCnnModelStore {
  TabCnnModelStore({this.cacheDirOverride, this.prefer = TabCnnVariant.gpfx});

  final String? cacheDirOverride;

  /// The variant to try first; the other is the fallback.
  final TabCnnVariant prefer;

  static const _base = 'https://huggingface.co/cstr/tabcnn-onnx/resolve/main/';

  static const _onnxName = {
    TabCnnVariant.gpfx: 'tabcnn-gpfx.onnx',
    TabCnnVariant.vanilla: 'tabcnn.onnx',
  };

  ({OnnxModel model, CqtFilterBank cqt, TabCnnVariant variant})? _cached;

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

  /// Loads (and memoises) the preferred model + shared CQT blob, downloading on
  /// first use. Tries [prefer] then the other variant; returns null (with the
  /// resolved [variant]) if nothing can be obtained (offline) so callers gate
  /// the audio-tab path skip-if-absent.
  Future<({OnnxModel model, CqtFilterBank cqt, TabCnnVariant variant})?>
      load() async {
    if (_cached != null) return _cached;
    final blob = await _ensure('tabcnn-cqt.bin', 100000);
    if (blob == null) return null;
    final order = prefer == TabCnnVariant.gpfx
        ? const [TabCnnVariant.gpfx, TabCnnVariant.vanilla]
        : const [TabCnnVariant.vanilla, TabCnnVariant.gpfx];
    for (final v in order) {
      final onnx = await _ensure(_onnxName[v]!, 500000);
      if (onnx != null) {
        return _cached = (
          model: OnnxModel.fromBytes(onnx.readAsBytesSync()),
          cqt: CqtFilterBank.fromBytes(blob.readAsBytesSync()),
          variant: v,
        );
      }
    }
    return null;
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
