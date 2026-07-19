// The WHOLE transcription pipeline, end to end, on synthesized AUDIO — the
// "audio → sheet music" proof that the CLI can't give (bin/listen.dart must stay
// Flutter-free, but scoreToMusicXml pulls in crisp_notation, so the full-chain
// engraving is validated here where the flutter_test toolchain handles it).
//
//   PCM  → pyinF0 (S1)  → estimateTuningCents (S3)  → segmentNotes (S2)
//        → detectRhythm (W2)  → transcribeToScore (S5)  → scoreToMusicXml
//
// A clean synthetic C-major scale at 120 BPM must come out the far end as a
// MusicXML score whose pitched notes read C D E F G A B C, ascending.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/note_hmm.dart';
import 'package:comet_beat/core/audio/transcription/pyin.dart';
import 'package:comet_beat/core/audio/transcription/rhythm.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:comet_beat/core/audio/transcription/tuning.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;

double _hz(int midi, double offsetCents) =>
    440 * pow(2, (midi - 69) / 12 + offsetCents / 1200).toDouble();

/// A melody of [midis], one note per beat at [bpm]: each note sounds for 85% of
/// the beat then rests, so onsets land cleanly on the beat grid.
Float64List _melodyAudio(
  List<int> midis, {
  double bpm = 120,
  double cents = 0,
}) {
  final beat = 60 / bpm; // seconds per beat
  final noteSec = beat * 0.85;
  final restSec = beat * 0.15;
  final noteN = (noteSec * _sr).round();
  final restN = (restSec * _sr).round();
  final out = Float64List(midis.length * (noteN + restN));
  var off = 0;
  for (final m in midis) {
    final f = _hz(m, cents);
    for (var i = 0; i < noteN; i++) {
      // A short fade in/out avoids click transients that fool the onset detector.
      final env = min(1.0, min(i, noteN - i) / (0.01 * _sr));
      out[off + i] = 0.5 * env * sin(2 * pi * f * i / _sr);
    }
    off += noteN + restN;
  }
  return out;
}

// Ordered (step, octave) of the pitched notes in a single-part MusicXML string.
List<String> _pitches(String xml) {
  final notes = RegExp(r'<note\b[\s\S]*?</note>').allMatches(xml);
  final out = <String>[];
  for (final m in notes) {
    final block = m.group(0)!;
    if (block.contains('<rest')) continue;
    final step = RegExp(r'<step>([A-G])</step>').firstMatch(block)?.group(1);
    final oct = RegExp(r'<octave>(\d)</octave>').firstMatch(block)?.group(1);
    final alter = RegExp(r'<alter>(-?\d)</alter>').firstMatch(block)?.group(1);
    if (step != null) {
      out.add('$step${alter == null ? '' : (alter == '1' ? '#' : 'b')}$oct');
    }
  }
  return out;
}

Score _transcribeAudio(Float64List mono) {
  final track = pyinF0(mono);
  final ref = tunedReference(track);
  final notes = segmentNotes(track, a4: ref);
  final grid = detectRhythm(mono);
  return transcribeToScore(notes, grid);
}

void main() {
  test('a synth C-major scale becomes a MusicXML score reading C D E F G A B C',
      () {
    const scale = [60, 62, 64, 65, 67, 69, 71, 72];
    final score = _transcribeAudio(_melodyAudio(scale));
    final xml = scoreToMusicXml(score);

    expect(xml, contains('<score-partwise'));
    expect(score.measures, isNotEmpty);
    // The pitched notes, in order, spell the ascending scale (ignoring any
    // rests the bar-packer inserts). Octaves ascend C4 → C5.
    final steps = [for (final p in _pitches(xml)) p[0]];
    expect(steps, ['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C']);
    expect(_pitches(xml).first, 'C4');
    expect(_pitches(xml).last, 'C5');
  });

  test('a scale sung 35 cents flat still engraves the right notes (tuning fix)',
      () {
    const scale = [60, 62, 64, 65, 67];
    final score = _transcribeAudio(_melodyAudio(scale, cents: -35));
    final steps = [for (final p in _pitches(scoreToMusicXml(score))) p[0]];
    expect(steps, ['C', 'D', 'E', 'F', 'G']);
  });

  test('the detected tempo lands near the true 120 BPM', () {
    final grid = detectRhythm(_melodyAudio(const [60, 62, 64, 65, 67, 69]));
    // Octave errors (60/240) are the usual failure; anything in-band is a pass.
    expect(grid.bpm, greaterThan(90));
    expect(grid.bpm, lessThan(150));
  });
}
