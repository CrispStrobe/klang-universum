// scoreFromMidi (the app's MIDI importer) must recover the notated tempo from
// the Set-Tempo meta — the mirror of scoreToMidi writing it — so an imported
// MIDI plays / plays-along / re-exports at its real speed, not a default.

import 'package:comet_beat/core/notation/multi_part_export.dart';
import 'package:comet_beat/features/games/songs/import/midi_import.dart';
// Note: crisp_notation ALSO exports a scoreFromMidi; hide it so `scoreFromMidi`
// resolves to the app importer under test.
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, Score, Tempo, TimeSignature, scoreToMidi;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovers the tempo from a single-track file', () {
    final midi = scoreToMidi(
      Score.simple(
        notes: 'c4:q d4 e4 f4',
        timeSignature: TimeSignature.fourFour,
        tempo: const Tempo(90),
      ),
    );
    final back = scoreFromMidi(midi);
    expect(back.tempo, isNotNull);
    expect(back.tempo!.bpm, closeTo(90, 0.5));
  });

  test('recovers the tempo from a format-1 file (tempo may sit on track 0)',
      () {
    final midi = multiPartToMidi(
      MultiPartScore([
        Score.simple(notes: 'c4:q d4 e4 f4', tempo: const Tempo(72)),
      ]),
    );
    final back = scoreFromMidi(midi);
    expect(back.tempo?.bpm, closeTo(72, 0.5));
  });

  test('a very fast tempo round-trips', () {
    final midi = scoreToMidi(
      Score.simple(notes: 'c4:q d4', tempo: const Tempo(180)),
    );
    expect(scoreFromMidi(midi).tempo?.bpm, closeTo(180, 1));
  });
}
