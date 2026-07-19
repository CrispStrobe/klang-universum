// lib/core/audio/transcription/transcribe.dart
//
// Transcription — S5 integration (docs/TRANSCRIPTION_HANDOFF.md). Combines any
// transcriber's NoteEvents (Worker 1 monophonic OR Worker 3 neural) with
// Worker 2's RhythmGrid into a crisp_notation Score — after which the shipped
// MusicXML / MIDI export is free.
//
// Pipeline: quantise onto the beat grid (Worker 2's quantizeToGrid) → a
// CHORD-aware step timeline (cut at every note boundary; each slice's sounding
// notes become one chord note-head; held chords merge) → greedy note-value
// decomposition + barline splits (same shape as the Loop Mixer's groove_notation)
// → Score. Monophonic input is unchanged; a polyphonic transcriber's chords now
// survive. Notes split across barlines tie; independent voices re-articulate at
// each onset (true voice/staff separation is a W-NOTATION follow-up).

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
/// [beatsPerBar]/4 bars, CHORD-aware (simultaneous notes become one chord
/// note-head, so a polyphonic transcriber's chords survive), gaps filled with
/// rests, greedy note values tied across barlines. Monophonic input is
/// unaffected — every vertical slice then holds at most one note.
///
/// It reads the harmony as a homophonic reduction: the timeline is cut at every
/// note start AND end, each slice engraves all notes sounding through it as a
/// chord, and adjacent slices with the same pitch set merge into one (held)
/// note. Independent voices are re-articulated at each new onset rather than
/// tied per-voice — acceptable for a first-pass lead sheet; true voice/staff
/// separation is a follow-up (W-NOTATION).
Score transcribeToScore(
  List<NoteEvent> notes,
  RhythmGrid grid, {
  Clef clef = Clef.treble,
  int beatsPerBar = 4,
}) {
  final stepsPerBar = beatsPerBar * _stepsPerBeat;
  final gridded = quantizeToGrid(notes, grid);

  // Note spans in steps: (startStep, endStep, midi).
  final events = [
    for (final g in gridded)
      () {
        final start = math.max(0, (g.startBeat * _stepsPerBeat).round());
        final dur = math.max(1, (g.beats * _stepsPerBeat).round());
        return (start: start, end: start + dur, midi: g.note.midi);
      }(),
  ];

  // Cut the timeline at every distinct note boundary; each segment's chord is
  // the set of notes sounding through it. Merge neighbouring segments that hold
  // the same pitch set (a sustained chord) so it isn't re-struck.
  final bounds = (<int>{0}..addAll([
          for (final e in events) ...[e.start, e.end],
        ]))
      .toList()
    ..sort();
  final cells = <({List<int> midis, int steps})>[];
  for (var i = 0; i < bounds.length - 1; i++) {
    final b = bounds[i];
    final steps = bounds[i + 1] - b;
    if (steps <= 0) continue;
    final active = <int>{
      for (final e in events)
        if (e.start <= b && b < e.end) e.midi,
    }.toList()
      ..sort();
    if (cells.isNotEmpty && _sameSet(cells.last.midis, active)) {
      final last = cells.removeLast();
      cells.add((midis: last.midis, steps: last.steps + steps));
    } else {
      cells.add((midis: active, steps: steps));
    }
  }

  // Pack cells into 4/4 bars, decomposing runs into note values. Every element
  // gets a unique id ('e0', 'e1', …) — the MIDI writer (scoreToMidi) only emits
  // notes it can find by id, so without these the MIDI export is silent.
  final measures = <Measure>[];
  var bar = <MusicElement>[];
  var posInBar = 0;
  var nextId = 0;
  void emit(List<int> midis, int steps) {
    var remaining = steps;
    while (remaining > 0) {
      final room = stepsPerBar - posInBar;
      final fit = math.min(remaining, room);
      final (chunk, duration) = _durations.firstWhere((d) => d.$1 <= fit);
      final id = 'e${nextId++}';
      // A note/chord that needs more than one value (an un-notatable length, or
      // one that crosses a barline) is TIED, not re-attacked: every chunk but
      // the last carries the sound into the next. Rests never tie.
      final tie = midis.isNotEmpty && (remaining - chunk) > 0;
      bar.add(
        midis.isEmpty
            ? RestElement(duration, id: id)
            : NoteElement(
                pitches: [for (final m in midis) _pitchFromMidi(m)],
                duration: duration,
                id: id,
                tieToNext: tie,
              ),
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
    emit(c.midis, c.steps);
  }
  // Complete the final bar with a rest so every measure is full.
  if (posInBar > 0) emit(const [], stepsPerBar - posInBar);

  return Score(
    clef: clef,
    timeSignature: TimeSignature(beatsPerBar, 4),
    tempo: grid.bpm > 0 ? Tempo(grid.bpm) : null,
    measures: measures,
  );
}

/// Whether two sorted midi lists hold the same pitch set.
bool _sameSet(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
