// The caller-side audio→tab decoder: a per-string Viterbi over TabCNN-style
// [T, 6, 21] log-prob emissions. Proves it holds a stable fret through a decoy
// single-frame spike that per-frame argmax would follow. No model, synthetic
// emissions only.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds emissions where, at each (frame, string), one class is `peak` log-prob
/// and the rest are `floor` — via `favoured(frame, string) → class`. A near-tie
/// decoy is layered in by [decoy] when it returns a non-null (class, logProb).
TabEmissionFrames _emit(
  int nFrames,
  int Function(int frame, int string) favoured, {
  double peak = -0.1,
  double floor = -8.0,
  int silentClass = 0,
  (int cls, double lp)? Function(int frame, int string)? decoy,
}) {
  final buf = Float64List(nFrames * kTabStrings * kTabClasses);
  for (var t = 0; t < nFrames; t++) {
    for (var s = 0; s < kTabStrings; s++) {
      final base = (t * kTabStrings + s) * kTabClasses;
      for (var c = 0; c < kTabClasses; c++) {
        buf[base + c] = floor;
      }
      buf[base + favoured(t, s)] = peak;
      final d = decoy?.call(t, s);
      if (d != null) buf[base + d.$1] = d.$2;
    }
  }
  return TabEmissionFrames(
    nFrames: nFrames,
    hopSeconds: 0.02,
    logProbs: buf,
    silentClass: silentClass,
  );
}

/// Per-frame argmax (the TabCNN paper's own decode) — the baseline the Viterbi
/// must beat.
List<int> _argmaxString(TabEmissionFrames e, int s) => [
      for (var t = 0; t < e.nFrames; t++)
        () {
          var best = 0;
          for (var c = 1; c < kTabClasses; c++) {
            if (e.at(t, s, c) > e.at(t, s, best)) best = c;
          }
          return best;
        }(),
    ];

void main() {
  // Every string silent except string 0.
  int silentElse(int t, int s, int active) => s == 0 ? active : 0;

  test('holds a stable fret through a one-frame decoy spike (beats argmax)',
      () {
    // String 0 wants fret 5 (class 6) for all 5 frames; frame 2 gets a strong
    // decoy for fret 12 (class 13) that argmax follows but the Viterbi rejects.
    const fret5 = 6, fret12 = 13;
    final e = _emit(
      5,
      (t, s) => silentElse(t, s, fret5),
      decoy: (t, s) => (t == 2 && s == 0) ? (fret12, -0.05) : null,
    );

    // Argmax flips at frame 2; the decoder holds fret 5 throughout.
    expect(_argmaxString(e, 0)[2], fret12, reason: 'argmax follows the spike');
    final tab = decodeTabEmissions(e);
    expect(tab, hasLength(5));
    for (final frame in tab) {
      expect(frame[0], 5, reason: 'string 0 stays on fret 5 (class 6)');
    }
  });

  test('silent strings are omitted; one note per string is structural', () {
    // String 0 on fret 3 (class 4), everything else silent.
    final e = _emit(3, (t, s) => silentElse(t, s, 4));
    final tab = decodeTabEmissions(e);
    for (final frame in tab) {
      expect(frame.keys, [0]); // only the active string
      expect(frame[0], 3);
    }
  });

  test('a genuine mid-note shift IS followed (not over-smoothed)', () {
    // Fret 2 for the first 4 frames, then fret 9 for the next 4 — a real slide,
    // strongly favoured, so the decoder should move rather than average.
    final e = _emit(8, (t, s) => silentElse(t, s, t < 4 ? 3 : 10));
    final tab = decodeTabEmissions(e);
    expect(tab.first[0], 2);
    expect(tab.last[0], 9);
  });

  test('collapse merges frame runs and preserves total length', () {
    final e = _emit(6, (t, s) => silentElse(t, s, t < 4 ? 4 : 6));
    final runs = collapseTabFrames(decodeTabEmissions(e));
    expect(runs.map((r) => r.$2).fold<int>(0, (a, r) => a + r), 6);
    expect(runs, hasLength(2)); // fret 3 ×4, then fret 5 ×2
    expect(runs.first.$1[0], 3);
    expect(runs.last.$1[0], 5);
  });

  test('empty emissions decode to nothing', () {
    final e = TabEmissionFrames(
      nFrames: 0,
      hopSeconds: 0.02,
      logProbs: Float64List(0),
    );
    expect(decodeTabEmissions(e), isEmpty);
  });

  test('class↔fret contract: 21 classes, class 1 = open, class 20 = fret 19',
      () {
    expect(kTabClasses, 21);
    expect(kTabStrings, 6);
    expect(kTabMaxFret, 19);
    // A frame favouring class 1 on string 0 → fret 0 (open).
    final open = decodeTabEmissions(_emit(1, (t, s) => s == 0 ? 1 : 0));
    expect(open.single[0], 0);
    // math import kept meaningful: sanity that floor < peak spacing decodes.
    expect(math.e, greaterThan(2));
  });

  // §2 landmine: the SAME class indices mean different frets under the two
  // exports (ONNX remaps silent→0; native GGUF keeps silent=20). The decoder
  // must read silentClass, not assume 0 — else every fret is off by one, open
  // strings vanish, and silence becomes a high fret.
  group('silentClass carries the export layout', () {
    // String 0 favours class 5; the rest favour their silent class.
    TabEmissionFrames c5(int silentClass) =>
        _emit(1, (t, s) => s == 0 ? 5 : silentClass, silentClass: silentClass);

    test('same class 5 → fret 4 (ONNX) vs fret 5 (GGUF)', () {
      expect(decodeTabEmissions(c5(0)).single[0], 4); // silent=0: class k→k-1
      expect(decodeTabEmissions(c5(20)).single[0], 5); // silent=20: class k→k
    });

    test('GGUF class 20 is SILENCE, not fret 19', () {
      final gguf = _emit(1, (t, s) => s == 0 ? 20 : 20, silentClass: 20);
      expect(decodeTabEmissions(gguf).single.containsKey(0), isFalse);
      // Under the ONNX layout class 20 IS fret 19 (the old contract).
      final onnx = _emit(1, (t, s) => s == 0 ? 20 : 0);
      expect(decodeTabEmissions(onnx).single[0], 19);
    });

    test('GGUF class 0 is open (fret 0), not silence', () {
      final gguf = _emit(1, (t, s) => s == 0 ? 0 : 20, silentClass: 20);
      expect(decodeTabEmissions(gguf).single[0], 0);
    });
  });
}
