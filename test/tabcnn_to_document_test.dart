// The audio→tab quantiser: per-frame frettings → a TabDocument with note
// durations. Pure (no model / no network).

import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show Fretting;
import 'package:comet_beat/features/games/composition/tabcnn_to_document.dart';
import 'package:crisp_notation/crisp_notation.dart' show NoteDuration, Tuning;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final guitar = Tuning.standardGuitar;

  test('collapses runs into columns with the nearest note value', () {
    // 120 bpm, hop ≈ 0.02322 s: a quarter (0.5 s) ≈ 21.5 frames, a half ≈ 43.
    final perFrame = <Fretting>[
      ...List.filled(21, {2: 0}), // G string open ≈ quarter
      ...List.filled(21, <int, int>{}), // silence ≈ quarter rest
      ...List.filled(43, {0: 3}), // high-E fret 3 ≈ half
    ];
    final doc =
        tabFramesToDocument(perFrame, tuning: guitar); // 120 bpm default

    expect(doc.columns, hasLength(3));
    expect(doc.columns[0].frets, {2: 0});
    expect(doc.columns[0].duration, NoteDuration.quarter);
    expect(doc.columns[1].isEmpty, isTrue); // a rest column
    expect(doc.columns[1].duration, NoteDuration.quarter);
    expect(doc.columns[2].frets, {0: 3});
    expect(doc.columns[2].duration, NoteDuration.half);
    expect(doc.tuning.name, guitar.name);
  });

  test('tempo scales the note values (same frames, faster = longer values)',
      () {
    final perFrame = List<Fretting>.filled(21, {0: 5}); // ~0.49 s of audio
    // 0.49 s @ 60 bpm = 0.49 beats → 1 eighth-step → eighth;
    // @ 240 bpm = 1.95 beats → 4 eighth-steps → half. Faster tempo, longer value.
    final slow = tabFramesToDocument(perFrame, tuning: guitar, tempoBpm: 60);
    final fast = tabFramesToDocument(perFrame, tuning: guitar, tempoBpm: 240);
    expect(slow.columns.single.duration, NoteDuration.eighth);
    expect(fast.columns.single.duration, NoteDuration.half);
  });

  test('drops sub-minFrames flicker but keeps real notes', () {
    final perFrame = <Fretting>[
      {0: 1}, // 1-frame flicker → dropped (< minFrames 2)
      ...List.filled(20, {0: 7}),
    ];
    final doc = tabFramesToDocument(perFrame, tuning: guitar);
    expect(doc.columns, hasLength(1));
    expect(doc.columns.single.frets, {0: 7});
  });

  test('all-silent / empty input yields a single empty column', () {
    final doc = tabFramesToDocument(
      const <Fretting>[],
      tuning: guitar,
    );
    expect(doc.columns, hasLength(1));
    expect(doc.columns.single.isEmpty, isTrue);
  });
}
