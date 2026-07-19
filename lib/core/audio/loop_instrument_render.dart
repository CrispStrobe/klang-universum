// Render a Loop Mixer pitched track's grid cells through an arbitrary
// [TrackerInstrument] voice — the loop-cell analog of score_instrument_render.
// A melodic loop track is just notes on a step grid ([PatternCell]s), the same
// model the tracker uses, so a saved "My Instruments" voice (a formula synth OR
// a sampled soundbank voice) can render it exactly like the tracker does its
// channels — instead of the fixed [Instrument] timbre [renderCells] uses.
//
// Pure Dart, so it is unit-testable and web-safe.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart'
    show LoopTiming, PatternCell;
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';

// Notes render on a fixed 120 BPM / 4-steps-per-beat grid (125 ms/step); the row
// count sustains each note for its cell's length.
const double _stepMs = 125;

/// Render one note held for [durMs] through [inst] (note on step 0, sustained).
Float64List _renderHeldNote(TrackerInstrument inst, int midi, int durMs) {
  final rows = (durMs / _stepMs).round().clamp(1, 100000);
  final cells = <TrackerCell>[
    TrackerCell(midi: midi),
    for (var i = 1; i < rows; i++) TrackerCell.empty,
  ];
  return inst.renderChannel(cells, TrackerTiming(rows: rows));
}

/// Render [cells] on [timing]'s step grid through [inst], returning a mono PCM
/// stem of `timing.totalSamples`. Each cell's note(s) are rendered through the
/// instrument for the cell's duration and placed at its time offset (chord
/// tones summed); notes ring their natural length, clipped at the loop end.
/// [transpose] shifts every note (key/scale), matching [renderCells].
Float64List renderCellsWithInstrument(
  List<PatternCell> cells,
  TrackerInstrument inst,
  LoopTiming timing, {
  int transpose = 0,
}) {
  final out = Float64List(timing.totalSamples);
  var step = 0;
  for (final cell in cells) {
    final startMs = timing.boundaryMs(step);
    final durMs = timing.boundaryMs(step + cell.steps) - startMs;
    final startSample = (startMs * kSampleRate) ~/ 1000;
    for (final m in cell.midis ?? const <int>[]) {
      final note = _renderHeldNote(inst, m + transpose, durMs);
      final limit = note.length;
      for (var i = 0; i < limit; i++) {
        final j = startSample + i;
        if (j >= out.length) break;
        out[j] += note[i];
      }
    }
    step += cell.steps;
  }
  return out;
}
