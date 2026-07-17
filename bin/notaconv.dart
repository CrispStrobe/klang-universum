// bin/notaconv.dart
//
// Headless notation bridge — converts BETWEEN tracker modules and notation files
// (Standard MIDI + MusicXML), both directions, through the ModuleDoc ↔ Score
// bridge (lib/core/audio/mod/module_notation.dart). Pure Dart, runs under plain
// `dart run` like bin/listen.dart. The conversion logic lives in lib and is
// unit-tested (test/module_notation_test.dart); this file is just I/O + routing.
//
//   Module → notation
//     dart run bin/notaconv.dart song.xm out.mid            # busiest channel → MIDI
//     dart run bin/notaconv.dart song.it out.mid --channel 2
//     dart run bin/notaconv.dart song.it out.mid --multi    # every channel → a MIDI track
//     dart run bin/notaconv.dart song.s3m out.xml           # all channels → MusicXML
//
//   Notation → module (the reverse)
//     dart run bin/notaconv.dart tune.mid out.it            # MIDI → a playable .it
//     dart run bin/notaconv.dart score.xml out.xm           # MusicXML → .xm (one channel/part)
//
//   Notation → notation
//     dart run bin/notaconv.dart tune.mid out.xml           # MIDI → MusicXML (and vice-versa)
//
// Rows quantize to a --steps-per-beat grid (default 4 = sixteenths); held runs
// become tied notes; a rest round-trips via a neutral note-off.

import 'dart:io';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_notation.dart';
// crisp_notation_core is the Flutter-free notation core (a dependency_override,
// re-exported via crisp_notation) — import it directly to stay Flutter-free.
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

const _extToFormat = <String, ModuleFormat>{
  'mod': ModuleFormat.mod,
  'xm': ModuleFormat.xm,
  's3m': ModuleFormat.s3m,
  'it': ModuleFormat.it,
};

String _ext(String path) => path.split('.').last.toLowerCase();
bool _isMidi(String e) => e == 'mid' || e == 'midi';
bool _isXml(String e) => e == 'xml' || e == 'musicxml';

void main(List<String> args) {
  final positional = <String>[];
  int? channel;
  var stepsPerBeat = 4;
  var multi = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--channel':
        channel = int.tryParse(i + 1 < args.length ? args[++i] : '');
      case '--steps-per-beat':
        stepsPerBeat = int.tryParse(i + 1 < args.length ? args[++i] : '') ?? 4;
      case '--multi':
        multi = true;
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
    stderr.writeln('usage: dart run bin/notaconv.dart <in> <out> '
        '[--channel N] [--steps-per-beat K] [--multi]\n'
        '  in/out by extension: module (.mod/.xm/.s3m/.it), MIDI (.mid), '
        'MusicXML (.xml)');
    exitCode = 2;
    return;
  }

  final inPath = positional[0], outPath = positional[1];
  final inFile = File(inPath);
  if (!inFile.existsSync()) {
    stderr.writeln('notaconv: no such file: $inPath');
    exitCode = 2;
    return;
  }
  final bytes = inFile.readAsBytesSync();
  final outExt = _ext(outPath);

  try {
    // ── Source: a module, a MIDI file, or a MusicXML file ─────────────────────
    if (sniffModuleFormat(bytes) != null) {
      _fromModule(
        parseAnyModule(bytes),
        outPath,
        outExt,
        channel: channel,
        stepsPerBeat: stepsPerBeat,
        multi: multi,
      );
    } else if (_isMidi(_ext(inPath))) {
      _fromScore(
        scoreFromMidi(bytes),
        outPath,
        outExt,
        stepsPerBeat: stepsPerBeat,
      );
    } else if (_isXml(_ext(inPath))) {
      _fromMultiPart(
        multiPartScoreFromMusicXml(String.fromCharCodes(bytes)),
        outPath,
        outExt: outExt,
        stepsPerBeat: stepsPerBeat,
      );
    } else {
      stderr
          .writeln('notaconv: unrecognized input (not a module, .mid or .xml)');
      exitCode = 1;
    }
  } catch (e) {
    stderr.writeln('notaconv: $e');
    exitCode = 1;
  }
}

// ── module → MIDI / MusicXML ──────────────────────────────────────────────────
void _fromModule(
  ModuleDoc doc,
  String outPath,
  String outExt, {
  int? channel,
  required int stepsPerBeat,
  required bool multi,
}) {
  if (doc.channelCount == 0) {
    stderr.writeln('notaconv: the module has no channels');
    exitCode = 1;
    return;
  }
  final tempo = doc.initialTempo.toDouble();
  if (_isMidi(outExt)) {
    if (multi) {
      final mp = moduleToMultiPart(doc, stepsPerBeat: stepsPerBeat);
      final smf = multiPartToMidi(mp.score, quarterBpm: tempo);
      File(outPath).writeAsBytesSync(smf);
      _ok(doc, outPath, '${mp.score.parts.length} tracks, ${smf.length} bytes');
    } else {
      final ch = channel ?? busiestChannel(doc);
      if (ch < 0 || ch >= doc.channelCount) {
        stderr.writeln('notaconv: channel $ch out of range '
            '(0..${doc.channelCount - 1})');
        exitCode = 2;
        return;
      }
      final score = moduleChannelToScore(doc, ch, stepsPerBeat: stepsPerBeat);
      final smf = scoreToMidi(score, quarterBpm: tempo);
      File(outPath).writeAsBytesSync(smf);
      _ok(doc, outPath, 'channel $ch, ${smf.length} bytes');
    }
  } else if (_isXml(outExt)) {
    final xml = moduleToMusicXml(doc, stepsPerBeat: stepsPerBeat);
    File(outPath).writeAsStringSync(xml);
    _ok(doc, outPath, '${xml.length} bytes MusicXML');
  } else {
    stderr.writeln('notaconv: module → .$outExt not supported '
        '(use .mid or .xml; for module→module use modconv)');
    exitCode = 2;
  }
}

// ── a single Score (from MIDI) → module / MusicXML ───────────────────────────
void _fromScore(
  Score score,
  String outPath,
  String outExt, {
  required int stepsPerBeat,
}) {
  final fmt = _extToFormat[outExt];
  if (fmt != null) {
    final doc =
        scoreToModuleDoc(score, stepsPerBeat: stepsPerBeat, format: fmt);
    File(outPath).writeAsBytesSync(convertDocTo(doc, fmt));
    stdout.writeln('notaconv: MIDI → .$outExt ($outPath)');
  } else if (_isXml(outExt)) {
    File(outPath).writeAsStringSync(scoreToMusicXml(score));
    stdout.writeln('notaconv: MIDI → MusicXML ($outPath)');
  } else {
    stderr.writeln('notaconv: MIDI → .$outExt not supported');
    exitCode = 2;
  }
}

// ── a MultiPartScore (from MusicXML) → module / MIDI ─────────────────────────
void _fromMultiPart(
  MultiPartScore mp,
  String outPath, {
  required String outExt,
  required int stepsPerBeat,
}) {
  final fmt = _extToFormat[outExt];
  if (fmt != null) {
    final doc =
        multiPartToModuleDoc(mp, stepsPerBeat: stepsPerBeat, format: fmt);
    File(outPath).writeAsBytesSync(convertDocTo(doc, fmt));
    stdout.writeln('notaconv: MusicXML → .$outExt '
        '(${mp.parts.length} parts → ${doc.channelCount} ch, $outPath)');
  } else if (_isMidi(outExt)) {
    File(outPath).writeAsBytesSync(multiPartToMidi(mp));
    stdout.writeln('notaconv: MusicXML → MIDI '
        '(${mp.parts.length} tracks, $outPath)');
  } else {
    stderr.writeln('notaconv: MusicXML → .$outExt not supported');
    exitCode = 2;
  }
}

void _ok(ModuleDoc doc, String outPath, String detail) {
  stdout.writeln('notaconv: ${doc.title.isEmpty ? '(untitled)' : doc.title} '
      '→ $outPath  ($detail)');
}
