// The Viterbi guitar-tab arranger — assigns (string, fret) minimising hand
// movement + chord span. Pure Dart, no widgets. Standard-guitar string MIDIs:
// E2=40 A2=45 D3=50 G3=55 B3=59 E4=64 (string index 0 = top line = high E).

import 'package:comet_beat/features/games/composition/tab_arranger.dart';
import 'package:crisp_notation/crisp_notation.dart' show Tuning;
import 'package:flutter_test/flutter_test.dart';

/// The sounding MIDI of every fretted position in an arrangement (flattened).
List<int> _sounding(List<Fretting> a, Tuning t, {int capo = 0}) => [
      for (final col in a)
        for (final e in col.entries)
          t.strings[e.key].midiNumber + e.value + capo,
    ];

void main() {
  final guitar = Tuning.standardGuitar;

  test('preserves column count and order (rests included)', () {
    final a = arrangeTab(
      [
        [60],
        const [], // rest
        [64],
      ],
      guitar,
    );
    expect(a, hasLength(3));
    expect(a[1], isEmpty); // the rest stays an empty column
  });

  test('every chosen position actually sounds the requested pitch', () {
    final tune = [60, 62, 64, 65, 67, 69, 71, 72].map((m) => [m]).toList();
    final a = arrangeTab(tune, guitar);
    expect(_sounding(a, guitar)..sort(), [60, 62, 64, 65, 67, 69, 71, 72]);
  });

  test(
      'stays in position instead of taking a distant lower fret (beats greedy)',
      () {
    // From D#5 (only high-E fret 11) to A#4: greedy picks the LOWER fret 6 on
    // the high-E string (a 5-fret jump); the arranger keeps the hand at 11 by
    // taking A#4 on the B string (fret 11) — same position, no jump.
    final a = arrangeTab(
      [
        [75], // D#5 → high-E fret 11
        [70], // A#4 → high-E f6  OR  B-string f11
      ],
      guitar,
    );
    expect(a[0].values.single, 11);
    expect(
      a[1].values.single,
      11,
      reason: 'held the position, not the low fret',
    );
    expect(_sounding(a, guitar)..sort(), [70, 75]);
  });

  test('a chord is seated on distinct strings with a small span', () {
    // C major triad C4 E4 G4 — should take one playable shape, one note/string.
    final a = arrangeTab(
      [
        [60, 64, 67],
      ],
      guitar,
    );
    final col = a.single;
    expect(col, hasLength(3)); // three distinct strings
    expect(col.keys.toSet(), hasLength(3));
    expect(_sounding(a, guitar)..sort(), [60, 64, 67]);
  });

  test('unreachable pitches are dropped, not crashed on', () {
    // 20 = way below the lowest string (E2=40); no position exists.
    final a = arrangeTab(
      [
        [20],
        [60],
      ],
      guitar,
    );
    expect(a[0], isEmpty); // dropped
    expect(_sounding(a, guitar), contains(60));
  });

  test('a capo shrinks the frets for the same fretted pitch', () {
    // G4 (67) is fretted (not an open string), so the capo cleanly shifts it.
    final open = arrangeTab(
      [
        [67],
      ],
      guitar,
    );
    final capo2 = arrangeTab(
      [
        [67],
      ],
      guitar,
      capo: 2,
    );
    expect(capo2.single.values.first, open.single.values.first - 2);
    expect(_sounding(capo2, guitar, capo: 2), [67]); // still sounds G4
  });

  test('empty input yields empty output', () {
    expect(arrangeTab(const [], guitar), isEmpty);
  });
}
