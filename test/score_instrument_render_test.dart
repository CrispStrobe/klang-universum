// renderScoreWithInstrument — play an engraved Score through an arbitrary
// TrackerInstrument voice (the bridge that lets a saved "My Instruments" voice
// sound a piece). Locks: it produces non-silent audio, longer pieces are
// longer, and a MultiPartScore sums its parts.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/score_instrument_render.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

SampleInstrument _voice() {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SampleInstrument('v', pcm);
}

double _peak(Float64List x) {
  var p = 0.0;
  for (final s in x) {
    if (s.abs() > p) p = s.abs();
  }
  return p;
}

void main() {
  test('renders a score through the instrument, non-silent', () {
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    final pcm = renderScoreWithInstrument(score, _voice());
    expect(pcm, isNotEmpty);
    expect(_peak(pcm), greaterThan(0.01));
  });

  test('a four-note phrase is longer than a one-note phrase', () {
    final one =
        renderScoreWithInstrument(Score.simple(notes: 'c4:q'), _voice());
    final four = renderScoreWithInstrument(
      Score.simple(notes: 'c4:q d4 e4 f4'),
      _voice(),
    );
    expect(four.length, greaterThan(one.length));
  });

  test('a slower tempo (bigger quarterMs) makes a longer render', () {
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    final fast = renderScoreWithInstrument(score, _voice(), quarterMs: 250);
    final slow = renderScoreWithInstrument(score, _voice(), quarterMs: 1000);
    expect(slow.length, greaterThan(fast.length));
  });

  test('a multi-part score sums to non-silent audio', () {
    final mp = MultiPartScore([
      Score.simple(notes: 'c4:q d4 e4 f4'),
      Score.simple(notes: 'g3:q a3 b3 c4'),
    ]);
    final pcm = renderMultiPartWithInstrument(mp, _voice());
    expect(pcm, isNotEmpty);
    expect(_peak(pcm), greaterThan(0.01));
  });
}
