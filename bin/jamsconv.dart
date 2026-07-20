// bin/jamsconv.dart — JAMS ⇄ notation converter (the `mus jams` subcommand).
//
// JAMS (JSON Annotated Music Specification) is the MIR ground-truth format.
// This converts BOTH directions, so a file can round-trip:
//
//   export:  .mid / .musicxml / .xml / .abc  →  .jams   (note_midi via scoreToJams)
//   import:  .jams  →  .mid   (a note_midi melody, via jamsToMidi)
//            .jams  →  .cho   (a chord annotation, via jamsToChordPro)
//
// The direction is chosen from the INPUT extension. Output path defaults to the
// input with the swapped extension, or pass it explicitly as the 2nd argument.
//
//   dart run bin/mus.dart jams song.mid            # → song.jams
//   dart run bin/mus.dart jams song.jams out.mid   # → out.mid
//
// Flutter-free: runs under plain `dart run`.

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/features/games/songs/import/jams.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.isEmpty) {
    stderr.writeln('usage: mus jams <input.{mid,musicxml,xml,abc,jams}> '
        '[output]\n'
        '  .mid/.musicxml/.abc → .jams   (export a melody as note_midi)\n'
        '  .jams               → .mid    (a note_midi melody)\n'
        '  .jams               → .cho    (a chord annotation, if no melody)');
    exitCode = 64;
    return;
  }

  final input = positional[0];
  final ext = input.split('.').last.toLowerCase();
  final bytes = File(input).readAsBytesSync();
  final base = input.replaceAll(RegExp(r'\.[^.]+$'), '');

  String out;
  List<int> data;
  try {
    if (ext == 'jams' || ext == 'json') {
      final json = utf8.decode(bytes);
      if (jamsMelodyNotes(json).isNotEmpty) {
        out = positional.length > 1 ? positional[1] : '$base.mid';
        data = jamsToMidi(json);
      } else {
        // No melody → export the chord annotation as ChordPro.
        out = positional.length > 1 ? positional[1] : '$base.cho';
        data = utf8.encode(jamsToChordPro(json));
      }
    } else {
      final score = switch (ext) {
        'mid' || 'midi' => scoreFromMidi(bytes),
        'abc' => scoreFromAbc(utf8.decode(bytes)),
        _ => scoreFromMusicXml(utf8.decode(bytes)),
      };
      out = positional.length > 1 ? positional[1] : '$base.jams';
      data = utf8.encode(scoreToJams(score, title: base.split('/').last));
    }
  } on FormatException catch (e) {
    stderr.writeln('jams: ${e.message}');
    exitCode = 65;
    return;
  }

  File(out).writeAsBytesSync(data);
  stdout.writeln('wrote $out (${data.length} bytes)');
}
