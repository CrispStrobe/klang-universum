// lib/core/audio/transcription/voices.dart
//
// W-NOTATION (final slice) — voice & staff separation, so independent lines are
// notated as such instead of re-articulated chords.
//
//  • separateVoices — assign overlapping notes to up to N monophonic VOICES by a
//    greedy streaming rule (a new note joins the free voice whose last pitch is
//    closest; simultaneous same-span notes stay together as a chord). A melody
//    over a held bass becomes two voices; a block chord stays one.
//  • toGrandStaff — split notes by pitch onto a treble + bass STAFF (the keyboard
//    grand staff), engrave each with the chord-aware engraver, share the detected
//    key, and pad both staves to the same length so they line up.
//
// Pure Dart, no model. Reuses transcribeToScore (chord-aware) + notation
// (key/spelling).

import 'dart:math' as math;

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/notation.dart';
import 'package:comet_beat/core/audio/transcription/transcribe.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Separate [notes] into up to [maxVoices] monophonic voices. Notes that share
/// an onset AND offset (within [tolMs]) stay together as a chord in one voice.
/// Returned voices are ordered highest-first (voice 1 = the top line).
List<List<NoteEvent>> separateVoices(
  List<NoteEvent> notes, {
  int maxVoices = 4,
  double tolMs = 40,
}) {
  if (notes.isEmpty) return const [];

  // 1. Group simultaneous same-span notes into chord units.
  final sorted = [...notes]..sort((a, b) => a.onMs.compareTo(b.onMs));
  final units = <List<NoteEvent>>[];
  for (final n in sorted) {
    List<NoteEvent>? match;
    for (final u in units) {
      if ((u.first.onMs - n.onMs).abs() <= tolMs &&
          (u.first.offMs - n.offMs).abs() <= tolMs) {
        match = u;
        break;
      }
    }
    if (match != null) {
      match.add(n);
    } else {
      units.add([n]);
    }
  }

  double unitOn(List<NoteEvent> u) => u.first.onMs;
  double unitOff(List<NoteEvent> u) => u.map((e) => e.offMs).reduce(math.max);
  int unitTop(List<NoteEvent> u) => u.map((e) => e.midi).reduce(math.max);

  // 2. Stream units into voices.
  final voices = <List<NoteEvent>>[];
  final lastOff = <double>[];
  final lastMidi = <int>[];
  units.sort((a, b) => unitOn(a).compareTo(unitOn(b)));
  for (final u in units) {
    var best = -1;
    var bestCost = double.infinity;
    for (var v = 0; v < voices.length; v++) {
      if (lastOff[v] <= unitOn(u) + tolMs) {
        final cost = (lastMidi[v] - unitTop(u)).abs().toDouble();
        if (cost < bestCost) {
          bestCost = cost;
          best = v;
        }
      }
    }
    if (best < 0 && voices.length < maxVoices) {
      best = voices.length;
      voices.add(<NoteEvent>[]);
      lastOff.add(double.negativeInfinity);
      lastMidi.add(unitTop(u));
    } else if (best < 0) {
      // No free voice and at the cap: force onto the pitch-closest voice.
      for (var v = 0; v < voices.length; v++) {
        final cost = (lastMidi[v] - unitTop(u)).abs().toDouble();
        if (cost < bestCost) {
          bestCost = cost;
          best = v;
        }
      }
    }
    voices[best].addAll(u);
    lastOff[best] = unitOff(u);
    lastMidi[best] = unitTop(u);
  }

  double median(List<NoteEvent> v) {
    final m = [for (final n in v) n.midi]..sort();
    return m[m.length ~/ 2].toDouble();
  }

  voices.sort((a, b) => median(b).compareTo(median(a)));
  return voices;
}

/// Engrave [notes] as a keyboard GRAND STAFF: notes at/above [splitMidi] (middle
/// C) go to the treble staff, the rest to the bass staff, each engraved
/// chord-aware, spelled for the whole piece's key, and padded so both staves
/// have the same number of bars.
GrandStaff toGrandStaff(
  List<NoteEvent> notes,
  RhythmGrid grid, {
  int splitMidi = 60,
  int beatsPerBar = 4,
}) {
  final fifths = estimateKey(notes).fifths;
  final upperNotes = [
    for (final n in notes)
      if (n.midi >= splitMidi) n,
  ];
  final lowerNotes = [
    for (final n in notes)
      if (n.midi < splitMidi) n,
  ];

  Score engrave(List<NoteEvent> ns, Clef clef) => respell(
        transcribeToScore(ns, grid, beatsPerBar: beatsPerBar, clef: clef),
        fifths: fifths,
      );

  var upper = engrave(upperNotes, Clef.treble);
  var lower = engrave(lowerNotes, Clef.bass);
  final bars = math.max(upper.measures.length, lower.measures.length);
  upper = _padToBars(upper, bars, beatsPerBar);
  lower = _padToBars(lower, bars, beatsPerBar);
  return GrandStaff(upper: upper, lower: lower);
}

/// Append whole-bar rests so [score] has [targetBars] measures (staff alignment).
Score _padToBars(Score score, int targetBars, int beatsPerBar) {
  if (score.measures.length >= targetBars) return score;
  final measures = [...score.measures];
  while (measures.length < targetBars) {
    final rest =
        RestElement(_barRest(beatsPerBar), id: 'pad${measures.length}');
    measures.add(Measure([rest]));
  }
  return Score(
    clef: score.clef,
    keySignature: score.keySignature,
    timeSignature: score.timeSignature,
    tempo: score.tempo,
    metadata: score.metadata,
    measures: measures,
  );
}

/// A single rest that fills a [beatsPerBar]/4 bar (whole rest for 4/4).
NoteDuration _barRest(int beatsPerBar) => switch (beatsPerBar) {
      4 => NoteDuration.whole,
      3 => const NoteDuration(DurationBase.half, dots: 1),
      2 => NoteDuration.half,
      _ => NoteDuration.whole,
    };
