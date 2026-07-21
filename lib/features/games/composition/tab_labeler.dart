// The SYMBOLIC arm of the tab work: a small ONNX emission scorer that scores
// candidate (string,fret) placements per note-column, so arrangeTab's Viterbi
// fingers more like a human than the hand-tuned heuristic. It is the score→tab
// mirror of the audio arm (TabCNN) — same [6,21] per-string LogSoftmax contract,
// but the input is symbolic (note-column pitch presence) instead of audio CQT.
//
// The model NEVER emits tab: it only scores positions arrangeTab already
// enumerated, and arrangeTab's transition cost + hard span cap stay the arbiter,
// so nothing unplayable can be introduced. Null-on-offline → the heuristic stays
// the guaranteed fallback. Trained on GuitarSet (CC BY 4.0).
//
// See docs/TAB_SYMBOLIC_LABELER_HANDOVER.md and tab_arranger.dart's
// TabPositionModel seam.
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show TabPositionModel;
import 'package:crisp_notation/crisp_notation.dart' show Tuning;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

// The input encoding — MUST match tool/tab_labeler/extract.py. A column is a
// multi-hot over MIDI [40..88]; the model sees a 9-column window centred on the
// target. Output is [6,21] per-string log-probs: class 0 = string silent, class
// k = fret k-1. String index 0 = high e (Tuning.standardGuitar order).
const int _pitchLo = 40;
const int _pitchHi = 88;
const int _pitchBins = _pitchHi - _pitchLo + 1; // 49
const int _window = 9;
const int _half = _window ~/ 2;
const int _numStrings = 6;
const int _numClasses = 21;
const String _inName = 'input';
const String _outName = 'output';

/// Resolves + caches the labeler ONNX (downloads on first use, or reads a
/// prebuilt file from `COMET_TABLABELER_DIR`). Mirrors [TabCnnModelStore].
class TabLabelerModelStore {
  TabLabelerModelStore({this.cacheDirOverride});

  final String? cacheDirOverride;

  static const _base =
      'https://huggingface.co/cstr/tab-labeler-onnx/resolve/main/';
  static const _onnxName = 'tab-labeler.onnx';

  OnnxModel? _cached;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_TABLABELER_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/models';
  }

  /// The model, or null when it can't be obtained (offline) so callers fall back
  /// to the heuristic arranger.
  Future<OnnxModel?> load() async {
    if (_cached != null) return _cached;
    final file = File('${cacheDir()}/$_onnxName');
    Uint8List? bytes;
    if (file.existsSync() && file.lengthSync() > 100000) {
      bytes = file.readAsBytesSync();
    } else {
      try {
        Directory(cacheDir()).createSync(recursive: true);
        final dl = await _get('$_base$_onnxName');
        if (dl != null && dl.length > 100000) {
          file.writeAsBytesSync(dl);
          bytes = dl;
        }
      } catch (_) {
        return null;
      }
    }
    if (bytes == null) return null;
    return _cached = OnnxModel.fromBytes(bytes);
  }

  static Future<Uint8List?> _get(String url) async {
    final client = HttpClient();
    try {
      client.userAgent = 'comet_beat-tablabeler';
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

/// A [TabPositionModel] backed by the symbolic labeler ONNX. Encodes the columns
/// exactly as training did, runs the model once for the whole sequence, and
/// returns, per column, `score[(string,fret)] = logprob[string][fret+1]` for
/// every position arrangeTab would enumerate — the log-prob IS the emission score
/// (higher = more idiomatic). Positions the model has no class for (fret > 19)
/// are omitted, so arrangeTab defers them to its heuristic.
class TabLabeler implements TabPositionModel {
  TabLabeler(this._model);

  final OnnxModel _model;

  /// Loads the model via [store] (or the default). Null when offline.
  static Future<TabLabeler?> load({TabLabelerModelStore? store}) async {
    final m = await (store ?? TabLabelerModelStore()).load();
    return m == null ? null : TabLabeler(m);
  }

  @override
  List<Map<(int string, int fret), double>?>? score(
    List<List<int>> columns,
    Tuning tuning, {
    int capo = 0,
    int maxFret = 20,
  }) {
    if (columns.isEmpty) return null;
    final n = columns.length;
    final enc = [for (final col in columns) _encode(col)];

    // Windowed input [n, bins, window, 1], row-major — the extract.py layout.
    final input = Float32List(n * _pitchBins * _window);
    for (var c = 0; c < n; c++) {
      for (var w = 0; w < _window; w++) {
        final k = c - _half + w;
        if (k < 0 || k >= n) continue;
        final e = enc[k];
        for (var b = 0; b < _pitchBins; b++) {
          input[(c * _pitchBins + b) * _window + w] = e[b];
        }
      }
    }

    final r = _model.run(
      {
        _inName: Tensor.float(input, [n, _pitchBins, _window, 1]),
      },
      const [_outName],
    )[_outName]!;
    final lp = r.f ?? r.asFloatList(); // [n*6*21] log-probs

    return [
      for (var c = 0; c < n; c++)
        _scoreColumn(
          columns[c],
          tuning,
          capo,
          maxFret,
          lp,
          c * _numStrings * _numClasses,
        ),
    ];
  }

  Map<(int, int), double>? _scoreColumn(
    List<int> pitches,
    Tuning tuning,
    int capo,
    int maxFret,
    List<double> lp,
    int base,
  ) {
    if (pitches.isEmpty) return null;
    final out = <(int, int), double>{};
    final strings = tuning.strings.length < _numStrings
        ? tuning.strings.length
        : _numStrings;
    for (final midi in pitches) {
      for (var s = 0; s < strings; s++) {
        final fret = midi - tuning.strings[s].midiNumber - capo;
        // Only positions the model has a class for (fret 0..19 → class 1..20).
        if (fret >= 0 && fret <= maxFret && fret < _numClasses - 1) {
          out[(s, fret)] = lp[base + s * _numClasses + (fret + 1)];
        }
      }
    }
    return out.isEmpty ? null : out;
  }

  Float32List _encode(List<int> col) {
    final v = Float32List(_pitchBins);
    for (final m in col) {
      if (m >= _pitchLo && m <= _pitchHi) v[m - _pitchLo] = 1.0;
    }
    return v;
  }
}
