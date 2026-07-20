// Bridges the cost-based tab arranger to crisp_notation's GPIF export: runs
// [arrangeTab] over a score's note columns and shapes the result as a
// [GpFretPlan] (`elementId -> {string: fret}`) so `scoreToGpif` /
// `multiPartToGpif` emit the arranged positions instead of the greedy per-pitch
// fallback. Flutter-free — used by `bin/tabconv.dart` and unit-testable without
// a widget tree.
import 'package:comet_beat/features/games/composition/tab_arranger.dart'
    show arrangeTab;
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Arranges [score]'s notes on [tuning] and returns a per-note GPIF fret plan.
///
/// Notes are taken in reading order (measures → elements), one arranger column
/// per [NoteElement]; rests don't contribute. The plan keys on each element's
/// `id` (importers assign them), so any element without an id is simply left to
/// the writer's `Tuning.fretFor`. Frets are absolute from the nut — the arranger
/// returns capo-relative frets (`midi − open − capo`), so [capo] is added back.
///
/// [maxFret] matches `Tuning.fretFor`'s default (24) so arranging never *loses*
/// a note that the plain fret-from-pitch path would keep. A column the arranger
/// can't place at all (every pitch out of reach) is left OUT of the plan rather
/// than pinned to nothing, so it too falls through to `fretFor` (which drops it
/// only if it is genuinely unreachable). Use [unreachableCount] to report how
/// many pitches no string can reach.
GpFretPlan gpFretPlanFor(
  Score score,
  Tuning tuning, {
  int capo = 0,
  int maxFret = 24,
}) {
  final notes = <NoteElement>[
    for (final m in score.measures)
      for (final e in m.elements)
        if (e is NoteElement) e,
  ];
  final columns = [
    for (final n in notes) [for (final p in n.pitches) p.midiNumber],
  ];
  final frettings = arrangeTab(columns, tuning, capo: capo, maxFret: maxFret);
  final plan = <String, Map<int, int>>{};
  for (var i = 0; i < notes.length && i < frettings.length; i++) {
    final id = notes[i].id;
    if (id == null || frettings[i].isEmpty) continue;
    plan[id] = {for (final e in frettings[i].entries) e.key: e.value + capo};
  }
  return plan;
}

/// How many of [score]'s sounding pitches no string of [tuning] can reach
/// (behind [capo], within [maxFret]) — i.e. how many notes any fretting must
/// drop. 0 means every note fits the instrument.
int unreachableCount(
  Score score,
  Tuning tuning, {
  int capo = 0,
  int maxFret = 24,
}) {
  var n = 0;
  for (final m in score.measures) {
    for (final e in m.elements) {
      if (e is! NoteElement) continue;
      for (final p in e.pitches) {
        final fits = tuning.strings.any((s) {
          final fret = p.midiNumber - s.midiNumber - capo;
          return fret >= 0 && fret <= maxFret;
        });
        if (!fits) n++;
      }
    }
  }
  return n;
}
