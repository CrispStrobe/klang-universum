// Mid-score bar changes anchored on a voice-2 note. The change setters run on
// the active voice, so a user in voice 2 can anchor a clef/key/tempo/repeat/
// volta/navigation change to a voice-2 element. These are bar-level (voice-
// independent); voice 2 reflows on the same grid, so _withMidScoreChanges now
// consults the bar's voice-2 ids and stamps the bar the anchor landed in.
// (Time changes and mid-*bar* inline clefs anchored on voice 2 remain a known
// limitation — time drives reflow's bar capacity by id, which needs more care.)

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s, {int octave = 4}) => Pitch(s, octave: octave);
const _quarter = NoteDuration(DurationBase.quarter);

/// Two 4/4 bars in each voice; returns the voice-2 ids (index 4 is the first
/// note of bar 1).
(ScoreDocument, List<String>) _twoBarsTwoVoices() {
  final d = ScoreDocument();
  for (var i = 0; i < 8; i++) {
    d.insertNote(_p(Step.c), _quarter); // voice 1: two full bars
  }
  d.setActiveVoice(1);
  final v2ids = [
    for (var i = 0; i < 8; i++) d.insertNote(_p(Step.e), _quarter),
  ];
  return (d, v2ids);
}

void main() {
  test('a clef change anchored on a voice-2 note stamps its bar', () {
    final (d, v2ids) = _twoBarsTwoVoices();
    d.setClefChangeAt(v2ids[4], Clef.bass); // first v2 note of bar 1

    final bars = d.buildScore().measures;
    expect(bars, hasLength(2));
    expect(bars[0].clefChange, isNull, reason: 'bar 0 is untouched');
    expect(
      bars[1].clefChange,
      Clef.bass,
      reason: 'the voice-2-anchored clef stamps the bar it landed in',
    );
  });

  test('a repeat-end anchored on a voice-2 note stamps its bar', () {
    final (d, v2ids) = _twoBarsTwoVoices();
    d.toggleRepeatEndAt(v2ids[7]); // last v2 note, bar 1

    final bars = d.buildScore().measures;
    expect(bars[1].endRepeat, isTrue);
    expect(bars[0].endRepeat, isFalse);
  });

  test('a voice-2-anchored change survives save → reopen', () {
    final (d, v2ids) = _twoBarsTwoVoices();
    d.setClefChangeAt(v2ids[4], Clef.bass);

    // On reopen the change re-anchors to the bar's first voice-1 element, so it
    // still stamps the same bar.
    final rebuilt = (ScoreDocument()..loadScore(d.buildScore())).buildScore();
    expect(rebuilt.measures[1].clefChange, Clef.bass);
  });
}
