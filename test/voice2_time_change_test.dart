// Meter (time-signature) changes with voice 2 present. A meter change is
// bar-level — it re-bars the whole system — but _timeChanges anchors it to one
// element id, which lives in only one voice's stream. Passing the raw map to the
// other voice's reflow left that voice at the old capacity, desyncing the
// barlines. _timeChangesFor re-keys the change onto each voice by cumulative
// onset, so a change entered in either voice re-bars both.

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s) => Pitch(s);
const _q = NoteDuration(DurationBase.quarter);

List<int> _v1Counts(Score s) => [for (final b in s.measures) b.elements.length];
List<int> _v2Counts(Score s) => [for (final b in s.measures) b.voice2.length];

void main() {
  // 7 quarters per voice; a 2/4 change after the first (4/4) bar re-bars the
  // remaining 3 quarters as 2/4: bars of 2, then 1. BOTH voices must agree.
  test('a voice-1-anchored meter change re-bars voice 2 too', () {
    final d = ScoreDocument();
    for (var i = 0; i < 4; i++) {
      d.insertNote(_p(Step.c), _q); // bar 0 (4/4)
    }
    final changeId = d.insertNote(_p(Step.c), _q); // bar 1 start
    d.insertNote(_p(Step.c), _q);
    d.insertNote(_p(Step.c), _q);
    d.setActiveVoice(1);
    for (var i = 0; i < 7; i++) {
      d.insertNote(_p(Step.e), _q);
    }
    d.setActiveVoice(0);
    d.setTimeChangeAt(changeId, TimeSignature.twoFour);

    final s = d.buildScore();
    expect(s.measures[1].timeChange, TimeSignature.twoFour);
    expect(_v1Counts(s), [4, 2, 1]);
    expect(_v2Counts(s), [4, 2, 1], reason: 'voice 2 re-bars with voice 1');
  });

  test('a voice-2-anchored meter change re-bars voice 1 too', () {
    final d = ScoreDocument();
    for (var i = 0; i < 7; i++) {
      d.insertNote(_p(Step.c), _q); // voice 1: 7 quarters
    }
    d.setActiveVoice(1);
    final v2 = [for (var i = 0; i < 7; i++) d.insertNote(_p(Step.e), _q)];
    d.setTimeChangeAt(v2[4], TimeSignature.twoFour); // onset 1 whole = v1 bar 1

    final s = d.buildScore();
    expect(s.measures[1].timeChange, TimeSignature.twoFour);
    expect(_v1Counts(s), [4, 2, 1], reason: 'voice 1 re-bars from a v2 anchor');
    expect(_v2Counts(s), [4, 2, 1]);
  });

  test('a voice-1-only meter change is unaffected (byte-identical bars)', () {
    final d = ScoreDocument();
    for (var i = 0; i < 4; i++) {
      d.insertNote(_p(Step.c), _q);
    }
    final id = d.insertNote(_p(Step.c), _q);
    d.insertNote(_p(Step.c), _q);
    d.insertNote(_p(Step.c), _q);
    d.setTimeChangeAt(id, TimeSignature.twoFour);

    final s = d.buildScore();
    expect(_v1Counts(s), [4, 2, 1]);
    expect(s.measures[1].timeChange, TimeSignature.twoFour);
    expect(s.measures.every((b) => b.voice2.isEmpty), isTrue);
  });

  test('meter change + voice 2 survives save → reopen', () {
    final d = ScoreDocument();
    for (var i = 0; i < 4; i++) {
      d.insertNote(_p(Step.c), _q);
    }
    final changeId = d.insertNote(_p(Step.c), _q);
    d.insertNote(_p(Step.c), _q);
    d.insertNote(_p(Step.c), _q);
    d.setActiveVoice(1);
    for (var i = 0; i < 7; i++) {
      d.insertNote(_p(Step.e), _q);
    }
    d.setActiveVoice(0);
    d.setTimeChangeAt(changeId, TimeSignature.twoFour);

    final s = (ScoreDocument()..loadScore(d.buildScore())).buildScore();
    expect(s.measures[1].timeChange, TimeSignature.twoFour);
    expect(_v1Counts(s), [4, 2, 1]);
    expect(_v2Counts(s), [4, 2, 1]);
  });
}
