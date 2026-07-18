// The editable tablature model behind the Tab Workshop (B1). A [TabDocument] is
// a tuning + an ordered list of [TabColumn]s (time steps). Each column pins a
// fret to one or more strings (a chord). It converts *to* a crisp_notation
// [Score] for engraving/playback (carrying [TabVoicing]s so the user's explicit
// string choice is honoured, not re-derived) and *from* a Score so an imported
// file (Guitar Pro/MusicXML/…) becomes editable as tab.
//
// Pure Dart (no Flutter) so the whole model is unit-testable.

import 'package:crisp_notation/crisp_notation.dart';

/// A playing technique attached to a tab note. Rendered by the tab engine via
/// the matching `Score` lists (bends / slides / note marks / legato slurs).
enum TabTechnique { hammer, slide, bend, dead, ghost, harmonic }

/// One time-step in a [TabDocument]: a map of string index → fret (a chord when
/// more than one), the played [duration], and any [techniques]. String index
/// 0 = the top tab line (highest-sounding string), matching [Tuning].
class TabColumn {
  final Map<int, int> frets;
  final NoteDuration duration;
  final Set<TabTechnique> techniques;

  /// An optional chord diagram shown above this column (display-only — it does
  /// not affect [TabDocument.toScore]).
  final ChordDiagram? chord;

  const TabColumn({
    this.frets = const {},
    this.duration = NoteDuration.quarter,
    this.techniques = const {},
    this.chord,
  });

  bool get isEmpty => frets.isEmpty;

  TabColumn withFret(int string, int fret) => TabColumn(
        frets: {...frets, string: fret},
        duration: duration,
        techniques: techniques,
        chord: chord,
      );

  TabColumn withoutString(int string) => TabColumn(
        frets: {
          for (final e in frets.entries)
            if (e.key != string) e.key: e.value,
        },
        duration: duration,
        techniques: techniques,
        chord: chord,
      );

  TabColumn withDuration(NoteDuration d) => TabColumn(
        frets: frets,
        duration: d,
        techniques: techniques,
        chord: chord,
      );

  /// Adds [t] if absent, else removes it.
  TabColumn toggleTechnique(TabTechnique t) => TabColumn(
        frets: frets,
        duration: duration,
        techniques: techniques.contains(t)
            ? ({...techniques}..remove(t))
            : {...techniques, t},
        chord: chord,
      );

  /// Sets (or clears, when null) this column's chord diagram.
  TabColumn withChord(ChordDiagram? c) => TabColumn(
        frets: frets,
        duration: duration,
        techniques: techniques,
        chord: c,
      );
}

/// The selectable note durations, each with its length in eighth-note steps
/// (kept integral so columns tile 4/4 bars cleanly). Ordered long→short.
const List<(NoteDuration, int)> kTabDurations = [
  (NoteDuration.whole, 8),
  (NoteDuration(DurationBase.half, dots: 1), 6),
  (NoteDuration.half, 4),
  (NoteDuration(DurationBase.quarter, dots: 1), 3),
  (NoteDuration.quarter, 2),
  (NoteDuration.eighth, 1),
];

int _stepsOf(NoteDuration d) {
  for (final (dur, steps) in kTabDurations) {
    if (dur == d) return steps;
  }
  return 2; // default: a quarter
}

/// C-major natural spellings by pitch class; others take the natural below + ♯.
const Map<int, Step> _naturalSteps = {
  0: Step.c,
  2: Step.d,
  4: Step.e,
  5: Step.f,
  7: Step.g,
  9: Step.a,
  11: Step.b,
};

Pitch pitchFromMidi(int midi) {
  final pc = midi % 12;
  final octave = midi ~/ 12 - 1;
  final natural = _naturalSteps[pc];
  if (natural != null) return Pitch(natural, octave: octave);
  return Pitch(_naturalSteps[pc - 1]!, alter: 1, octave: octave);
}

/// A mutable tablature document: [tuning] + a list of [columns].
class TabDocument {
  Tuning tuning;
  final List<TabColumn> columns;

  TabDocument({required this.tuning, List<TabColumn>? columns})
      : columns = columns ?? <TabColumn>[];

  /// A blank document with [initialColumns] empty columns.
  factory TabDocument.blank(Tuning tuning, {int initialColumns = 8}) =>
      TabDocument(
        tuning: tuning,
        columns: List.generate(initialColumns, (_) => const TabColumn()),
      );

  int get stringCount => tuning.stringCount;

  /// Grows [columns] so index [col] exists (padding with empty columns).
  void _ensure(int col) {
    while (columns.length <= col) {
      columns.add(const TabColumn());
    }
  }

  /// Sets the [fret] on [string] at [col] (creating the column if needed).
  void setFret(int col, int string, int fret) {
    _ensure(col);
    columns[col] = columns[col].withFret(string, fret);
  }

  /// Clears [string] at [col] (leaving other strings in that column).
  void clearCell(int col, int string) {
    if (col < columns.length) {
      columns[col] = columns[col].withoutString(string);
    }
  }

  /// Sets the [duration] of the column at [col].
  void setDuration(int col, NoteDuration duration) {
    _ensure(col);
    columns[col] = columns[col].withDuration(duration);
  }

  /// Toggles technique [t] on the column at [col].
  void toggleTechnique(int col, TabTechnique t) {
    _ensure(col);
    columns[col] = columns[col].toggleTechnique(t);
  }

  /// Sets (or clears, when null) the chord diagram on the column at [col].
  void setChord(int col, ChordDiagram? chord) {
    _ensure(col);
    columns[col] = columns[col].withChord(chord);
  }

  /// Inserts an empty column at [col].
  void insertColumn(int col) =>
      columns.insert(col.clamp(0, columns.length), const TabColumn());

  /// Removes the column at [col] (no-op if out of range or it's the last one).
  void removeColumn(int col) {
    if (columns.length > 1 && col >= 0 && col < columns.length) {
      columns.removeAt(col);
    }
  }

  /// Engraves the document as a [Score] with [TabVoicing]s pinning each note to
  /// its authored strings. Columns tile into ≤8-step (4/4) bars without ever
  /// splitting a note across a barline (so voicing ids stay 1:1 with columns).
  Score toScore() {
    final measures = <Measure>[];
    final voicings = <TabVoicing>[];
    final bends = <Bend>[];
    final marks = <TabNoteMark>[];
    final slides = <TabSlide>[];
    final slurs = <Slur>[];
    var bar = <MusicElement>[];
    var barSteps = 0;

    // Next noteful column after each index — the legato slur target for hammer.
    int? nextNoteful(int from) {
      for (var i = from + 1; i < columns.length; i++) {
        if (!columns[i].isEmpty) return i;
      }
      return null;
    }

    for (var c = 0; c < columns.length; c++) {
      final col = columns[c];
      final steps = _stepsOf(col.duration);
      if (barSteps > 0 && barSteps + steps > 8) {
        measures.add(Measure(bar));
        bar = <MusicElement>[];
        barSteps = 0;
      }
      if (col.isEmpty) {
        bar.add(RestElement(col.duration));
      } else {
        final entries = col.frets.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final pitches = [
          for (final e in entries)
            pitchFromMidi(tuning.strings[e.key].midiNumber + e.value),
        ];
        final id = 't$c';
        bar.add(NoteElement(pitches: pitches, duration: col.duration, id: id));
        voicings.add(TabVoicing(id, [for (final e in entries) e.key]));
        for (final t in col.techniques) {
          switch (t) {
            case TabTechnique.bend:
              bends.add(Bend(id));
            case TabTechnique.slide:
              slides.add(TabSlide(id, SlideInOut.outUpward));
            case TabTechnique.dead:
              marks.add(TabNoteMark(id, TabNoteStyle.dead));
            case TabTechnique.ghost:
              marks.add(TabNoteMark(id, TabNoteStyle.ghost));
            case TabTechnique.harmonic:
              marks.add(TabNoteMark(id, TabNoteStyle.harmonic));
            case TabTechnique.hammer:
              final n = nextNoteful(c);
              if (n != null) slurs.add(Slur(id, 't$n'));
          }
        }
      }
      barSteps += steps;
    }
    if (bar.isNotEmpty) measures.add(Measure(bar));
    if (measures.isEmpty) {
      measures.add(const Measure([RestElement(NoteDuration.whole)]));
    }
    return Score(
      clef: Clef.treble,
      measures: measures,
      tabVoicings: voicings,
      bends: bends,
      tabNoteMarks: marks,
      slideInOuts: slides,
      slurs: slurs,
    );
  }

  /// A `(midi pitches, ms)` timeline for `AudioService.playTimedChords`, at
  /// [bpm] (a quarter note = 60000/bpm ms).
  List<(List<int>, int)> toPlaybackEvents({int bpm = 120}) {
    final eighthMs = (60000 / bpm / 2).round();
    return [
      for (final col in columns)
        (
          [
            for (final e
                in (col.frets.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key))))
              tuning.strings[e.key].midiNumber + e.value,
          ],
          _stepsOf(col.duration) * eighthMs,
        ),
    ];
  }

  /// Builds an editable document from an arbitrary [score], placing each note on
  /// its lowest-fret string for [tuning] (unreachable pitches are dropped). Best
  /// effort: complex/high polyphony flattens to what the fretboard can play.
  static TabDocument fromScore(Score score, Tuning tuning) {
    final columns = <TabColumn>[];
    for (final measure in score.measures) {
      for (final el in measure.elements) {
        if (el is NoteElement) {
          final frets = <int, int>{};
          for (final p in el.pitches) {
            final sf = tuning.fretFor(p);
            if (sf != null) frets.putIfAbsent(sf.$1, () => sf.$2);
          }
          columns.add(TabColumn(frets: frets, duration: el.duration));
        } else if (el is RestElement) {
          columns.add(TabColumn(duration: el.duration));
        }
      }
    }
    if (columns.isEmpty) columns.add(const TabColumn());
    return TabDocument(tuning: tuning, columns: columns);
  }
}
