// lib/features/games/composition/groove_notation.dart
//
// Groove → crisp_notation Score: the Loop Mixer's live-engraving bridge (the
// app's signature "you're quietly writing notation" trick, scaled up from
// Colour Melody). Pattern cells are data (loop_engine.dart), so engraving is
// a pure mapping: eighth-note steps → note/rest durations, 8 steps per 4/4
// bar, cells split at barlines.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:klang_universum/core/audio/loop_engine.dart';

const _naturalSteps = {
  0: Step.c,
  2: Step.d,
  4: Step.e,
  5: Step.f,
  7: Step.g,
  9: Step.a,
  11: Step.b,
};

/// MIDI number → [Pitch]. The groove content is all C-major naturals; a
/// chromatic midi (future content) is spelled as a sharp.
Pitch pitchFromMidi(int midi) {
  final pitchClass = midi % 12;
  final octave = midi ~/ 12 - 1;
  final step = _naturalSteps[pitchClass];
  if (step != null) return Pitch(step, octave: octave);
  return Pitch(_naturalSteps[pitchClass - 1]!, alter: 1, octave: octave);
}

// Greedy decomposition of an eighth-step run into engravable durations.
const _durations = [
  (8, NoteDuration.whole),
  (6, NoteDuration(DurationBase.half, dots: 1)),
  (4, NoteDuration.half),
  (3, NoteDuration(DurationBase.quarter, dots: 1)),
  (2, NoteDuration.quarter),
  (1, NoteDuration.eighth),
];

/// Engraves groove [cells] (eighth-step grid) as a Score: 4/4 bars of
/// [LoopTiming.stepsPerBar] steps, cells split at barlines, runs decomposed
/// greedily (8 → whole, 3 → dotted quarter, …). Split notes re-attack rather
/// than tie — fine for a groove lead-sheet.
Score grooveScore(List<PatternCell> cells, {Clef clef = Clef.treble}) {
  final measures = <Measure>[];
  var bar = <MusicElement>[];
  var posInBar = 0;

  void emit(List<int>? midis, int steps) {
    var remaining = steps;
    while (remaining > 0) {
      final roomInBar = LoopTiming.stepsPerBar - posInBar;
      final fit = remaining > roomInBar ? roomInBar : remaining;
      final (chunk, duration) = _durations.firstWhere((d) => d.$1 <= fit);
      if (midis == null || midis.isEmpty) {
        bar.add(RestElement(duration));
      } else {
        bar.add(
          NoteElement(
            pitches: [for (final m in midis) pitchFromMidi(m)],
            duration: duration,
          ),
        );
      }
      posInBar += chunk;
      remaining -= chunk;
      if (posInBar == LoopTiming.stepsPerBar) {
        measures.add(Measure(bar));
        bar = <MusicElement>[];
        posInBar = 0;
      }
    }
  }

  for (final cell in cells) {
    emit(cell.midis, cell.steps);
  }
  if (bar.isNotEmpty) measures.add(Measure(bar));

  return Score(clef: clef, measures: measures);
}
