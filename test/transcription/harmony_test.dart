// W-HARMONY decode tests (deterministic, no model): argmax decode, the
// index→chord mapping, and run-merging into timed events. The CQT front-end
// parity is covered by harmony_cqt_test.dart; end-to-end model runs by
// harmony_model_test.dart (model-gated).
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/harmony.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodeChordLogits picks the per-frame argmax', () {
    // 2 frames × 25 classes: frame0 peaks at class 0 (C), frame1 at class 24 (N).
    final logits = Float32List(2 * 25);
    logits[0] = 5.0; // frame0 → C
    logits[25 + 24] = 5.0; // frame1 → N
    expect(decodeChordLogits(logits), [0, 24]);
  });

  test('chordFromIndex maps the interleaved maj/min vocabulary', () {
    expect(chordFromIndex(0, 0, 1).label, 'C');
    expect(chordFromIndex(0, 0, 1).rootPc, 0);
    expect(chordFromIndex(0, 0, 1).quality, 'maj');
    expect(chordFromIndex(1, 0, 1).label, 'C:min');
    expect(chordFromIndex(1, 0, 1).quality, 'min');
    expect(chordFromIndex(19, 0, 1).label, 'A:min'); // 19 → A min
    expect(chordFromIndex(19, 0, 1).rootPc, 9); // A = pc 9
    final n = chordFromIndex(24, 0, 1);
    expect((n.label, n.rootPc, n.quality), ('N', -1, 'N'));
  });

  test('btcChordLabels is the 25-class maj/min vocabulary', () {
    expect(btcChordLabels.length, 25);
    expect(btcChordLabels.first, 'C');
    expect(btcChordLabels.last, 'N');
  });
}
