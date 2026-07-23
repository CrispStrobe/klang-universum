// Render AudioService [Segment]s (freqs + ms, i.e. chords + rests on a timeline)
// through an ARBITRARY [TrackerInstrument] voice — the segment-timeline analog of
// loop_instrument_render's renderCellsWithInstrument. This is what lets the app's
// global playback voice be ANY sound-library instrument (Tonal / Chiptune /
// Plucked / FM / Subtractive procedural voices, or a sampled asset) instead of
// just the four additive [Instrument] timbres.
//
// Each segment starts at its cumulative time offset; each note rings its natural
// length (tails overlap into later segments, like a real instrument); an
// empty-freqs segment is a rest (silence). Pure Dart → unit-testable, web-safe.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show Segment, kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';

// Notes render on the same fixed 120 BPM / 4-steps-per-beat grid (125 ms/step)
// that loop_instrument_render uses, so a held note's row count == its duration.
const double _stepMs = 125;

int _freqToMidi(double f) =>
    f <= 0 ? 0 : (69 + 12 * (log(f / 440) / ln2)).round();

/// Render one note held for [durMs] through [inst] (struck on step 0, sustained
/// over the remaining rows so it rings its natural length).
Float64List _renderHeldNote(TrackerInstrument inst, int midi, int durMs) {
  final rows = (durMs / _stepMs).round().clamp(1, 100000);
  final cells = <TrackerCell>[
    TrackerCell(midi: midi),
    for (var i = 1; i < rows; i++) TrackerCell.empty,
  ];
  return inst.renderChannel(cells, TrackerTiming(rows: rows));
}

/// Renders [segments] through [inst], returning mono PCM (`-1..1` floats).
/// [gain] scales the whole result (0..1). Rests (empty `freqs`) are silence;
/// chord tones within a segment are summed; note tails ring past their segment.
Float64List renderSegmentsThroughInstrument(
  List<Segment> segments,
  TrackerInstrument inst, {
  double gain = 1.0,
}) {
  // Cumulative sample offset of each segment along the timeline.
  final offsets = <int>[];
  var cursor = 0;
  for (final s in segments) {
    offsets.add(cursor);
    cursor += (s.ms / 1000 * kSampleRate).round();
  }
  var maxEnd = cursor; // timeline is at least its nominal length
  final placed = <(int, Float64List)>[];
  for (var i = 0; i < segments.length; i++) {
    for (final f in segments[i].freqs) {
      final note = _renderHeldNote(inst, _freqToMidi(f), segments[i].ms);
      placed.add((offsets[i], note));
      final end = offsets[i] + note.length;
      if (end > maxEnd) maxEnd = end;
    }
  }
  final out = Float64List(maxEnd);
  for (final (off, note) in placed) {
    for (var i = 0; i < note.length; i++) {
      out[off + i] += note[i];
    }
  }
  if (gain != 1.0) {
    for (var i = 0; i < out.length; i++) {
      out[i] *= gain;
    }
  }
  return out;
}
