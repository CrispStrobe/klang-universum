// lib/core/audio/transcription/transcribe.dart
//
// Transcription — S5 integration (docs/TRANSCRIPTION_HANDOFF.md). Combines any
// transcriber's NoteEvents (Worker 1 monophonic OR Worker 3 neural) with
// Worker 2's RhythmGrid into a crisp_notation Score — after which the shipped
// MusicXML / MIDI export is free.
//
// Pipeline: quantise onto the beat grid (Worker 2's quantizeToGrid) → a
// monophonic step timeline (rests fill gaps, overlaps truncate) → greedy
// note-value decomposition + barline splits (same shape as the Loop Mixer's
// groove_notation) → Score. Split notes re-attack rather than tie — acceptable
// for a first-pass lead sheet.

import 'dart:math' as math;

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/rhythm.dart'
    show quantizeToGrid;
// The pure core (NOT the Flutter barrel, which reaches Flutter via midi_pitch)
// so this module — and the whole pipeline — runs under `dart run` in the
// bin/listen.dart CLI. Score, the MusicXML writer, etc. all live in core.
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Sixteenth-note resolution: 4 steps per beat.
const int _stepsPerBeat = 4;

/// Greedy step→duration table (largest first), for a 16-step (4/4) bar.
const List<(int, NoteDuration)> _durations = [
  (16, NoteDuration.whole),
  (12, NoteDuration(DurationBase.half, dots: 1)),
  (8, NoteDuration.half),
  (6, NoteDuration(DurationBase.quarter, dots: 1)),
  (4, NoteDuration.quarter),
  (3, NoteDuration(DurationBase.eighth, dots: 1)),
  (2, NoteDuration.eighth),
  (1, NoteDuration(DurationBase.sixteenth)),
];

/// Engraves [notes] (from any transcriber) quantised to [grid] as a [Score]:
/// [beatsPerBar]/4 bars, a monophonic melody line (the highest note wins any
/// overlap), gaps filled with rests, greedy note values split at barlines.
Score transcribeToScore(
  List<NoteEvent> notes,
  RhythmGrid grid, {
  Clef clef = Clef.treble,
  int beatsPerBar = 4,
}) {
  final stepsPerBar = beatsPerBar * _stepsPerBeat;
  final gridded = quantizeToGrid(notes, grid);

  // One monophonic timeline in steps: (startStep, durSteps, midi), sorted.
  final events = [
    for (final g in gridded)
      (
        start: math.max(0, (g.startBeat * _stepsPerBeat).round()),
        dur: math.max(1, (g.beats * _stepsPerBeat).round()),
        midi: g.note.midi,
      ),
  ]..sort((a, b) => a.start.compareTo(b.start));

  // Collapse to (pitch | rest, steps) cells: rests bridge gaps, a note is
  // truncated where the next one begins (monophonic).
  final cells = <({int? midi, int steps})>[];
  var pos = 0;
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (e.start < pos) continue; // overlaps the note already placed — drop it
    if (e.start > pos) {
      cells.add((midi: null, steps: e.start - pos));
      pos = e.start;
    }
    var dur = e.dur;
    if (i + 1 < events.length && e.start + dur > events[i + 1].start) {
      dur = events[i + 1].start - e.start;
    }
    if (dur < 1) dur = 1;
    cells.add((midi: e.midi, steps: dur));
    pos += dur;
  }

  // Pack cells into 4/4 bars, decomposing runs into note values.
  final measures = <Measure>[];
  var bar = <MusicElement>[];
  var posInBar = 0;
  void emit(int? midi, int steps) {
    var remaining = steps;
    while (remaining > 0) {
      final room = stepsPerBar - posInBar;
      final fit = math.min(remaining, room);
      final (chunk, duration) = _durations.firstWhere((d) => d.$1 <= fit);
      bar.add(
        midi == null
            ? RestElement(duration)
            : NoteElement(pitches: [_pitchFromMidi(midi)], duration: duration),
      );
      posInBar += chunk;
      remaining -= chunk;
      if (posInBar == stepsPerBar) {
        measures.add(Measure(bar));
        bar = <MusicElement>[];
        posInBar = 0;
      }
    }
  }

  for (final c in cells) {
    emit(c.midi, c.steps);
  }
  // Complete the final bar with a rest so every measure is full.
  if (posInBar > 0) emit(null, stepsPerBar - posInBar);

  return Score(
    clef: clef,
    timeSignature: TimeSignature(beatsPerBar, 4),
    tempo: grid.bpm > 0 ? Tempo(grid.bpm) : null,
    measures: measures,
  );
}

const _naturalStep = {
  0: Step.c,
  2: Step.d,
  4: Step.e,
  5: Step.f,
  7: Step.g,
  9: Step.a,
  11: Step.b,
};

/// MIDI number → [Pitch]; a chromatic pitch class is spelled as a sharp.
/// (A local copy of the app's `pitchFromMidi` — kept here so this module stays
/// Flutter-free for the `dart run` CLI.)
Pitch _pitchFromMidi(int midi) {
  final pc = midi % 12;
  final octave = midi ~/ 12 - 1;
  final step = _naturalStep[pc];
  if (step != null) return Pitch(step, octave: octave);
  return Pitch(_naturalStep[pc - 1]!, alter: 1, octave: octave);
}
