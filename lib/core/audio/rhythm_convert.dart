// lib/core/audio/rhythm_convert.dart
//
// Converts a quantised rhythm (from rhythm_quantize.dart) into the app's grid
// models, so a recorded performance becomes editable everywhere. Roadmap step 3
// ("conversion to all our models"): from a `RhythmQuantization` you get
//   • a Tracker channel column  → the Tracker already exports Score / MusicXML /
//     MIDI / module and saves to the Song Book, so this is the notation bridge;
//   • a Loop Mixer `DrumRowsPattern` → a recorded beat drops straight into the
//     groovebox.
// A hit's musical position (beat) is grid-independent, so it re-places cleanly
// onto any target grid. Per-hit pitch (Tracker) / drum (Loop Mixer) come from
// the caller — the rhythm engine itself is label-agnostic. Pure Dart.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/rhythm_quantize.dart';
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// A quantised hit's position in quarter-note beats from the capture start
/// (grid-independent, so it maps onto any target subdivision).
double beatOfHit(QuantizedHit hit, RhythmResolution resolution) =>
    hit.step / resolution.stepsPerBeat;

/// Re-place [hit] (measured on the [from] grid) onto a target grid of
/// [targetStepsPerBeat] steps per beat, returning the nearest target step.
int hitToStep(
  QuantizedHit hit,
  RhythmResolution from,
  int targetStepsPerBeat,
) =>
    (beatOfHit(hit, from) * targetStepsPerBeat).round();

/// Loop Mixer / Tracker eighth grid: steps per beat (8 steps per 4/4 bar).
const _eighthStepsPerBeat = LoopTiming.stepsPerBar ~/ LoopTiming.beatsPerBar;

/// Convert to a single **Tracker channel column** of [length] rows at
/// [stepsPerBeat] rows per beat: a note at each hit's step, its pitch from
/// [midiOf] and (optionally) stamped with [instrument]. Hits that fall on or
/// past [length] are dropped (a longer capture is truncated, not wrapped —
/// tracker patterns have a fixed length the caller chooses). If two hits land on
/// the same row the later one wins.
List<TrackerCell> toTrackerColumn(
  RhythmQuantization q, {
  required int length,
  required int stepsPerBeat,
  required int Function(QuantizedHit hit) midiOf,
  int instrument = 0,
}) {
  final cells = List<TrackerCell>.filled(length, TrackerCell.empty);
  for (final h in q.hits) {
    final row = hitToStep(h, q.resolution, stepsPerBeat);
    if (row >= 0 && row < length) {
      cells[row] = TrackerCell(midi: midiOf(h), instrument: instrument);
    }
  }
  return cells;
}

/// Convert to a Loop Mixer [DrumRowsPattern] (a fixed eighth grid of [steps]
/// steps): each hit sets its step in the row for `drumOf(hit)`. A capture longer
/// than the pattern **wraps** by modulo, so extra bars fold into the loop.
DrumRowsPattern toDrumPattern(
  RhythmQuantization q, {
  required Drum Function(QuantizedHit hit) drumOf,
  int steps = kPatternSteps,
}) {
  final rows = {
    for (final d in Drum.values) d: List<bool>.filled(steps, false),
  };
  for (final h in q.hits) {
    final step = hitToStep(h, q.resolution, _eighthStepsPerBeat) % steps;
    rows[drumOf(h)]![step] = true;
  }
  return DrumRowsPattern(rows);
}
