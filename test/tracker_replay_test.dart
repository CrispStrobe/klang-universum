// tracker_replay — the effect-column replayer. Phase 1: the volume domain
// (Cxx set-volume, Axy volume-slide). Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const timing = TrackerTiming(rows: 4);
  // A flat 1.0 stem so the gain envelope is directly observable.
  Float64List flatStem() => Float64List.fromList(
        List<double>.filled(timing.totalSamples, 1.0),
      );

  double at(Float64List b, int row, TrackerTiming t) =>
      b[t.stepStartSample(row) + t.stepStartSample(1) ~/ 2];

  test('no commands → the stem is returned unchanged (identity)', () {
    final cells = [for (var i = 0; i < 4; i++) const TrackerCell(midi: 60)];
    final stem = flatStem();
    final out = applyVolumeColumn(stem, cells, timing);
    expect(identical(out, stem), isTrue);
  });

  test('Cxx sets the channel volume level', () {
    final cells = [
      const TrackerCell(midi: 60, fxCmd: 0xC, fxParam: 0x20), // C20 -> 32/64
      const TrackerCell(midi: 60),
      const TrackerCell(midi: 60, fxCmd: 0xC, fxParam: 0x40), // C40 -> full
      const TrackerCell(midi: 60),
    ];
    final out = applyVolumeColumn(flatStem(), cells, timing);
    expect(at(out, 0, timing), closeTo(0.5, 0.02)); // 32/64
    expect(at(out, 1, timing), closeTo(0.5, 0.02)); // persists
    expect(at(out, 2, timing), closeTo(1.0, 0.02)); // back to full
  });

  test('Axy volume-slide ramps the level down over the row and persists', () {
    final cells = [
      const TrackerCell(midi: 60, fxCmd: 0xC, fxParam: 0x40), // full
      const TrackerCell(midi: 60, fxCmd: 0xA, fxParam: 0x04), // A04 slide down
      const TrackerCell(midi: 60),
      const TrackerCell(midi: 60),
    ];
    final out = applyVolumeColumn(flatStem(), cells, timing);
    // Row 1 ends lower than it started; row 2 stays at the reduced level.
    final s1 = timing.stepStartSample(1);
    final s2 = timing.stepStartSample(2);
    expect(out[s1], greaterThan(out[s2 - 1])); // ramped down within the row
    expect(at(out, 2, timing), lessThan(1.0)); // persisted, quieter
    expect(at(out, 2, timing), greaterThan(0.0));
  });

  test('a full A0F slide reaches silence and clamps', () {
    final cells = [
      const TrackerCell(midi: 60, fxCmd: 0xC, fxParam: 0x08), // low start
      const TrackerCell(midi: 60, fxCmd: 0xA, fxParam: 0x0F), // fast down
      const TrackerCell(midi: 60),
      const TrackerCell(midi: 60),
    ];
    final out = applyVolumeColumn(flatStem(), cells, timing);
    expect(at(out, 3, timing), 0.0); // clamped at 0, no negative gain
  });
}
