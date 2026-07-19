// S5 integration — NoteEvents + RhythmGrid → a crisp_notation Score, and on to
// MusicXML. Synthetic notes on a known grid, asserting bar packing, durations,
// rests, barline splits and a valid MusicXML render.

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

NoteEvent _n(int midi, double on, double off) =>
    (midi: midi, onMs: on, offMs: off, confidence: 1.0);

// One 4/4 bar at 120 BPM: beats at 0, 500, 1000, 1500, 2000 ms.
const _grid = (
  bpm: 120.0,
  beatMs: [0.0, 500.0, 1000.0, 1500.0, 2000.0],
  onsetMs: <double>[],
);

void main() {
  test('four quarter notes fill one 4/4 bar', () {
    final score = transcribeToScore(
      [
        _n(60, 0, 500),
        _n(62, 500, 1000),
        _n(64, 1000, 1500),
        _n(65, 1500, 2000),
      ],
      _grid,
    );

    expect(score.measures, hasLength(1));
    final els = score.measures.first.elements;
    final noteEls = els.whereType<NoteElement>().toList();
    expect(noteEls, hasLength(4));
    expect(
      noteEls.every((n) => n.duration.base == DurationBase.quarter),
      isTrue,
    );
    expect(noteEls.first.pitches.single, const Pitch(Step.c)); // C4
    expect(score.timeSignature?.beats, 4);
    expect(score.tempo?.bpm, 120);
  });

  test('a gap becomes a rest and an eighth is half a beat', () {
    final score = transcribeToScore(
      [
        _n(60, 0, 250), // an eighth on beat 0
        _n(62, 500, 1000), // then a quarter on beat 1 (a gap between)
      ],
      _grid,
    );
    final els = score.measures.first.elements;
    expect(els.first, isA<NoteElement>());
    expect((els.first as NoteElement).duration.base, DurationBase.eighth);
    expect(els.any((e) => e is RestElement), isTrue, reason: 'the gap');
  });

  test('a note across the barline splits into two measures', () {
    const grid2 = (
      bpm: 120.0,
      beatMs: <double>[0, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000],
      onsetMs: <double>[],
    );
    // A note from beat 3 to beat 5 crosses the 4/4 barline.
    final score = transcribeToScore([_n(60, 1500, 2500)], grid2);
    expect(score.measures.length, greaterThanOrEqualTo(2));
  });

  test('the transcribed Score renders valid MusicXML', () {
    final score = transcribeToScore(
      [
        _n(60, 0, 500),
        _n(62, 500, 1000),
        _n(64, 1000, 2000),
      ],
      _grid,
    );
    final xml = multiPartToMusicXml(
      MultiPartScore([score]),
      partNames: const ['Melody'],
    );
    expect(xml, contains('<score-partwise'));
    expect(xml, contains('<step>C</step>'));
  });

  test('no notes yields an empty score, never throws', () {
    expect(transcribeToScore(const [], _grid).measures, isEmpty);
  });
}
