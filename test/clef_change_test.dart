// Mid-score clef changes — the first feature built on the element-id-anchor
// mechanism (docs/WORKSHOP_PARITY.md, Cause 1). A clef change is stored against
// an element id, not a bar number, so it rides along as the music is re-barred
// by reflow; buildScore stamps it onto whichever bar that element lands in.
//
// This deliberately does NOT need the full "bars as source of truth" flip: the
// change is a side-map on the existing flat document, applied after reflow.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

/// The clefChange stamped on each bar (null = none), in order.
List<Clef?> _clefChangesPerBar(ScoreDocument d) =>
    [for (final m in d.buildScore().measures) m.clefChange];

void main() {
  // Fills [count] quarter notes and returns their ids in order.
  List<String> fill(ScoreDocument d, int count) =>
      [for (var i = 0; i < count; i++) d.insertNote(_p(Step.c), _quarter)];

  test('a clef change lands on the bar of its anchor element', () {
    final d = ScoreDocument(); // 4/4 → 4 quarters per bar
    final ids = fill(d, 8); // two full bars
    d.setClefChangeAt(ids[4], Clef.bass); // first note of bar 1

    expect(_clefChangesPerBar(d), [null, Clef.bass]);
    expect(
      d.buildScore().measures[1].clefChange,
      Clef.bass,
      reason: 'the change is drawn where bar 1 begins',
    );
  });

  test('the anchor rides re-barring: insert earlier and it stays with its note',
      () {
    final d = ScoreDocument();
    final ids = fill(d, 8);
    d.setClefChangeAt(ids[4], Clef.bass); // start of bar 1
    expect(_clefChangesPerBar(d), [null, Clef.bass]);

    // Insert a note at the very front → everything shifts one slot right, so the
    // anchored note is now the LAST of bar 1, and bar 2 begins with it... no:
    // it moves to bar 1's end, pushing the change bar. The point is the change
    // follows the element, not a fixed bar index.
    d.selectIndex(0);
    d.insertNote(_p(Step.d), _quarter); // inserted after selection (index 1)
    final bars = d.buildScore().measures;
    // Find which bar now carries the change and assert it's where the anchor is.
    final anchorBar = bars.indexWhere(
      (m) => m.elements.any((e) => e.id == ids[4]),
    );
    expect(bars[anchorBar].clefChange, Clef.bass);
    expect(
      bars.where((m) => m.clefChange == Clef.bass),
      hasLength(1),
      reason: 'exactly one bar carries the change',
    );
  });

  test('a redundant change (same as running clef) is not drawn', () {
    final d = ScoreDocument(); // treble
    final ids = fill(d, 8);
    d.setClefChangeAt(ids[4], Clef.treble); // same as the document clef
    expect(
      _clefChangesPerBar(d),
      [null, null],
      reason: 'no bar draws a treble→treble change',
    );
  });

  test('only the changing bar is marked; the clef carries forward', () {
    final d = ScoreDocument();
    final ids = fill(d, 12); // three bars
    d.setClefChangeAt(ids[4], Clef.bass); // bar 1 → bass
    // bar 2 stays bass (engine carries it), so no second mark.
    expect(_clefChangesPerBar(d), [null, Clef.bass, null]);
  });

  test('setting, clearing, and undo', () {
    final d = ScoreDocument();
    final ids = fill(d, 8);
    d.setClefChangeAt(ids[4], Clef.bass);
    expect(d.clefChanges, {ids[4]: Clef.bass});

    d.setClefChangeAt(ids[4], null); // clear
    expect(d.clefChanges, isEmpty);
    expect(_clefChangesPerBar(d), [null, null]);

    d.undo(); // brings the change back
    expect(d.clefChanges, {ids[4]: Clef.bass});
    expect(d.buildScore().measures[1].clefChange, Clef.bass);
  });

  test('an unknown anchor id is ignored', () {
    final d = ScoreDocument();
    fill(d, 4);
    d.setClefChangeAt('does-not-exist', Clef.bass);
    expect(d.clefChanges, isEmpty);
  });

  test('no clef changes → buildScore is untouched (goldens stay valid)', () {
    final d = ScoreDocument();
    fill(d, 8);
    expect(
      d.buildScore().measures.every((m) => m.clefChange == null),
      isTrue,
    );
  });

  test('save → reopen preserves a mid-score clef change', () {
    final src = ScoreDocument();
    final ids = fill(src, 8);
    src.setClefChangeAt(ids[4], Clef.bass);

    // Through MusicXML, the real Save → Open path.
    final parsed = scoreFromMusicXml(scoreToMusicXml(src.buildScore()));
    final reopened = ScoreDocument()..loadScore(parsed);

    expect(
      reopened.buildScore().measures[1].clefChange,
      Clef.bass,
      reason: 'the clef change survives the round-trip',
    );
  });
}
