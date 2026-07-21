// bin/musicrenderconv.dart
//
// Headless importer for muspy / PDMX "MusicRender" JSON — MuseScore's own JSON
// export, the format the PDMX corpus (openmusic/pdmx, ~254k public-domain
// scores) ships in. Converts a `.json` score to MIDI, MusicXML or ABC. Pure
// Dart, runs under plain `dart run` like bin/notaconv.dart. The import logic
// lives in crisp_notation_core (musicrender_reader.dart, unit-tested via
// packages/crisp_notation_core/test/musicrender_test.dart); this is I/O + routing.
//
//   Single file (output format by extension):
//     dart run bin/musicrenderconv.dart score.json out.mid        # note-exact JSON→MIDI
//     dart run bin/musicrenderconv.dart score.json out.mid --via-notation
//     dart run bin/musicrenderconv.dart score.json out.musicxml   # JSON→Score→MusicXML
//     dart run bin/musicrenderconv.dart score.json out.abc
//
//   Batch a directory of .json (basenames preserved):
//     dart run bin/musicrenderconv.dart json_dir/ out_dir/ --to mid
//     dart run bin/musicrenderconv.dart json_dir/ out_dir/ --to musicxml
//
// Two MIDI paths: the DEFAULT `.mid` route is `musicRenderToMidi` — note-exact,
// no notation quantization, the pure-Dart equivalent of muspy's write_midi.
// `--via-notation` instead routes JSON→Score→MIDI (sixteenth-grid, measured),
// to exercise the notation model. MusicXML/ABC always go via the notation model.

import 'dart:io';

import 'package:comet_beat/core/notation/multi_part_export.dart';
// crisp_notation_core is the Flutter-free notation core (a dependency_override,
// re-exported via crisp_notation) — import it directly to stay Flutter-free.
// ignore: depend_on_referenced_packages
import 'package:crisp_notation_core/crisp_notation_core.dart';

String _ext(String path) => path.split('.').last.toLowerCase();
bool _isMidi(String e) => e == 'mid' || e == 'midi';
bool _isXml(String e) => e == 'xml' || e == 'musicxml';

void main(List<String> args) {
  final positional = <String>[];
  var viaNotation = false;
  String? to;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--via-notation':
        viaNotation = true;
      case '--to':
        to = i + 1 < args.length ? args[++i].toLowerCase() : null;
      default:
        if (a.startsWith('-')) {
          stderr.writeln('musicrenderconv: unknown option $a');
          exitCode = 2;
          return;
        }
        positional.add(a);
    }
  }
  if (positional.length < 2) {
    stderr.writeln('usage: dart run bin/musicrenderconv.dart <in.json> <out> '
        '[--via-notation]\n'
        '       dart run bin/musicrenderconv.dart <json_dir/> <out_dir/> '
        '--to <mid|musicxml|abc>\n'
        '  out format by extension: MIDI (.mid), MusicXML (.musicxml/.xml), '
        'ABC (.abc)');
    exitCode = 2;
    return;
  }

  final inPath = positional[0], outPath = positional[1];

  // ── Batch mode: a directory of .json → a directory of <to> ────────────────
  if (FileSystemEntity.isDirectorySync(inPath)) {
    if (to == null) {
      stderr.writeln('musicrenderconv: --to <mid|musicxml|abc> is required for '
          'directory (batch) mode');
      exitCode = 2;
      return;
    }
    final outExt = _isXml(to) ? 'musicxml' : to;
    Directory(outPath).createSync(recursive: true);
    var ok = 0, fail = 0;
    for (final e in Directory(inPath).listSync()) {
      if (e is! File || _ext(e.path) != 'json') continue;
      final base = e.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
      final dst = '$outPath/$base.$outExt';
      try {
        _convert(e.readAsStringSync(), dst, to, viaNotation: viaNotation);
        ok++;
      } catch (err) {
        fail++;
        stderr.writeln('SKIP ${e.path}: $err');
      }
    }
    stdout.writeln('converted $ok, skipped $fail → $outPath');
    return;
  }

  // ── Single file ───────────────────────────────────────────────────────────
  final inFile = File(inPath);
  if (!inFile.existsSync()) {
    stderr.writeln('musicrenderconv: no such file: $inPath');
    exitCode = 2;
    return;
  }
  try {
    _convert(
      inFile.readAsStringSync(),
      outPath,
      _ext(outPath),
      viaNotation: viaNotation,
    );
    stdout.writeln('wrote $outPath');
  } catch (err) {
    stderr.writeln('musicrenderconv: $err');
    exitCode = 1;
  }
}

void _convert(
  String json,
  String outPath,
  String outExt, {
  required bool viaNotation,
}) {
  final out = File(outPath);
  if (_isMidi(outExt)) {
    // Default: note-exact transcode. --via-notation routes through the model.
    out.writeAsBytesSync(
      viaNotation
          ? multiPartToMidi(multiPartScoreFromMusicRender(json))
          : musicRenderToMidi(json),
    );
  } else if (_isXml(outExt)) {
    out.writeAsStringSync(
      multiPartToMusicXml(multiPartScoreFromMusicRender(json)),
    );
  } else if (outExt == 'abc') {
    out.writeAsStringSync(
      multiPartToAbc(multiPartScoreFromMusicRender(json)),
    );
  } else {
    throw FormatException(
      'unsupported output format: .$outExt (use .mid, .musicxml/.xml or .abc)',
    );
  }
}
