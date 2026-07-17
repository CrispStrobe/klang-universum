// bin/notaconv.dart
//
// Headless notation converter — turns a tracker module's melody into a Standard
// MIDI File, using the pure-Dart module readers + crisp_notation_core's Score→MIDI
// writer (the Flutter-free notation core, NOT the Flutter `crisp_notation` package).
// Runs under plain `dart run`, like bin/listen.dart / bin/modinfo.dart.
//
//   dart run bin/notaconv.dart song.xm out.mid            # busiest channel → MIDI
//   dart run bin/notaconv.dart song.it out.mid --channel 2
//   dart run bin/notaconv.dart song.mod out.mid --steps-per-beat 2
//
// One channel → one MIDI track. Rows are quantized to a [stepsPerBeat] grid
// (default 4 = sixteenths); a held run (a note ringing across empty rows) becomes
// tied notes. Deliberately simple: a melody dump, not a faithful module render.

import 'dart:io';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
// crisp_notation_core is the Flutter-free notation core (a dependency_override, so
// re-exported via crisp_notation) — import it directly to keep this CLI Flutter-free.
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> args) {
  final positional = <String>[];
  int? channel;
  var stepsPerBeat = 4;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--channel':
        channel = int.tryParse(i + 1 < args.length ? args[++i] : '');
      case '--steps-per-beat':
        stepsPerBeat = int.tryParse(i + 1 < args.length ? args[++i] : '') ?? 4;
      default:
        if (a.startsWith('-')) {
          stderr.writeln('notaconv: unknown option $a');
          exitCode = 2;
          return;
        }
        positional.add(a);
    }
  }
  if (positional.length < 2 || stepsPerBeat < 1) {
    stderr.writeln('usage: dart run bin/notaconv.dart <module> <out.mid> '
        '[--channel N] [--steps-per-beat K]');
    exitCode = 2;
    return;
  }

  final inFile = File(positional[0]);
  if (!inFile.existsSync()) {
    stderr.writeln('notaconv: no such file: ${positional[0]}');
    exitCode = 2;
    return;
  }
  final bytes = inFile.readAsBytesSync();
  if (sniffModuleFormat(bytes) == null) {
    stderr.writeln('notaconv: not a recognized module (.mod/.s3m/.xm/.it)');
    exitCode = 1;
    return;
  }

  final ModuleDoc doc;
  try {
    doc = parseAnyModule(bytes);
  } catch (e) {
    stderr.writeln('notaconv: failed to parse: $e');
    exitCode = 1;
    return;
  }

  // Flatten each channel's notes across the order list (a hold = -1).
  final chCount = doc.channelCount;
  if (chCount == 0) {
    stderr.writeln('notaconv: the module has no channels');
    exitCode = 1;
    return;
  }
  final flats = List.generate(chCount, (_) => <int>[]);
  for (final entry in doc.order) {
    if (entry < 0 || entry >= doc.patterns.length) continue;
    final pat = doc.patterns[entry];
    for (final row in pat.rows) {
      for (var c = 0; c < chCount; c++) {
        flats[c].add(c < row.length ? row[c].note : -1);
      }
    }
  }

  // Pick the channel: the requested one, or the busiest (most notes).
  final busiest = _busiest(flats);
  final ch = channel ?? busiest;
  if (ch < 0 || ch >= chCount) {
    stderr.writeln('notaconv: channel $ch out of range (0..${chCount - 1})');
    exitCode = 2;
    return;
  }

  final score = _runsToScore(_runs(flats[ch]), stepsPerBeat);
  final midi = scoreToMidi(score, quarterBpm: doc.initialTempo.toDouble());
  File(positional[1]).writeAsBytesSync(midi);
  final noteCount = flats[ch].where((m) => m >= 0).length;
  stdout.writeln('notaconv: ${doc.title.isEmpty ? positional[0] : doc.title} '
      'channel $ch ($noteCount notes) → ${positional[1]} (${midi.length} bytes)');
}

int _busiest(List<List<int>> flats) {
  var best = 0, bestCount = -1;
  for (var c = 0; c < flats.length; c++) {
    final count = flats[c].where((m) => m >= 0).length;
    if (count > bestCount) {
      bestCount = count;
      best = c;
    }
  }
  return best;
}

/// A flat per-row midi list into `(midi?, steps)` runs — a -1 row extends the
/// previous note (or is a leading rest). Mirrors the Tracker's cellRuns.
List<(int?, int)> _runs(List<int> midis) {
  final runs = <(int?, int)>[];
  for (final m in midis) {
    if (m < 0) {
      if (runs.isEmpty) {
        runs.add((null, 1));
      } else {
        final (pm, s) = runs.last;
        runs[runs.length - 1] = (pm, s + 1);
      }
    } else {
      runs.add((m, 1));
    }
  }
  return runs;
}

// --- Ported from tracker_notation.dart (Flutter-free notation core types) ------

const _pcSpelling = <(Step, int)>[
  (Step.c, 0),
  (Step.c, 1),
  (Step.d, 0),
  (Step.d, 1),
  (Step.e, 0),
  (Step.f, 0),
  (Step.f, 1),
  (Step.g, 0),
  (Step.g, 1),
  (Step.a, 0),
  (Step.a, 1),
  (Step.b, 0),
];

Pitch _pitchFromMidi(int midi) {
  final (step, alter) = _pcSpelling[midi % 12];
  return Pitch(step, alter: alter, octave: (midi ~/ 12) - 1);
}

List<(NoteDuration, int)> _durationLadder(int stepsPerBeat) {
  final stepsPerWhole = stepsPerBeat * 4;
  const candidates = <(NoteDuration, double)>[
    (NoteDuration(DurationBase.whole), 1.0),
    (NoteDuration(DurationBase.half, dots: 1), 0.75),
    (NoteDuration(DurationBase.half), 0.5),
    (NoteDuration(DurationBase.quarter, dots: 1), 0.375),
    (NoteDuration(DurationBase.quarter), 0.25),
    (NoteDuration(DurationBase.eighth, dots: 1), 0.1875),
    (NoteDuration(DurationBase.eighth), 0.125),
    (NoteDuration(DurationBase.sixteenth, dots: 1), 0.09375),
    (NoteDuration(DurationBase.sixteenth), 0.0625),
  ];
  final out = <(NoteDuration, int)>[];
  for (final (dur, frac) in candidates) {
    final steps = frac * stepsPerWhole;
    if ((steps - steps.roundToDouble()).abs() < 1e-9) {
      out.add((dur, steps.round()));
    }
  }
  return out;
}

List<NoteDuration> _decompose(int steps, List<(NoteDuration, int)> ladder) {
  final out = <NoteDuration>[];
  var rem = steps;
  while (rem > 0) {
    final piece =
        ladder.firstWhere((d) => d.$2 <= rem, orElse: () => ladder.last);
    out.add(piece.$1);
    rem -= piece.$2;
  }
  return out;
}

Score _runsToScore(List<(int?, int)> runs, int stepsPerBeat) {
  final ladder = _durationLadder(stepsPerBeat);
  final barSteps = stepsPerBeat * 4;
  final measures = <Measure>[];
  var current = <MusicElement>[];
  var posInBar = 0;
  var idCounter = 0;

  void closeBar() {
    measures.add(Measure(current));
    current = [];
    posInBar = 0;
  }

  for (final (midi, steps) in runs) {
    var rem = steps;
    while (rem > 0) {
      final avail = barSteps - posInBar;
      final take = rem < avail ? rem : avail;
      final pieces = _decompose(take, ladder);
      for (var i = 0; i < pieces.length; i++) {
        final lastOfRun = rem - take == 0 && i == pieces.length - 1;
        if (midi == null) {
          current.add(RestElement(pieces[i]));
        } else {
          current.add(
            NoteElement.note(
              _pitchFromMidi(midi),
              pieces[i],
              tieToNext: !lastOfRun,
              id: 'n${idCounter++}',
            ),
          );
        }
      }
      posInBar += take;
      rem -= take;
      if (posInBar >= barSteps) closeBar();
    }
  }
  if (current.isNotEmpty) closeBar();
  return Score(clef: Clef.treble, measures: measures);
}
