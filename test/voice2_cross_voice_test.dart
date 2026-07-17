// Cross-voice selection support in the model: voiceOfId lets the editor follow
// a tap to the tapped note's voice (mutations target the active voice, so a
// cross-voice edit needs the caret — and the active voice — to switch).

import 'package:comet_beat/features/workshop/model/score_document.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

Pitch _p(Step s) => Pitch(s);
const _q = NoteDuration(DurationBase.quarter);

void main() {
  test('voiceOfId reports the owning voice (or null)', () {
    final d = ScoreDocument();
    final v1 = d.insertNote(_p(Step.c), _q);
    d.setActiveVoice(1);
    final v2 = d.insertNote(_p(Step.e), _q);

    expect(d.voiceOfId(v1), 0);
    expect(d.voiceOfId(v2), 1);
    expect(d.voiceOfId('no-such-id'), isNull);
  });
}
