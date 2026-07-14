// Unit tests for importScore — the Workshop's unified, extension-dispatched file
// import. Pure (bytes in, Score out), so it exercises the format routing without
// a file picker.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/workshop/screens/composition_workshop_screen.dart';
import 'package:partitura/partitura.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('round-trips MusicXML by its extension', () {
    final xml = scoreToMusicXml(Score.simple(notes: 'c4:q d4 e4 f4'));
    final score = importScore('tune.musicxml', _bytes(xml));
    expect(score.measures, isNotEmpty);
  });

  test('reads ABC by its extension', () {
    final score = importScore('tune.abc', _bytes('X:1\nK:C\nCDEF|'));
    expect(score.measures, isNotEmpty);
  });

  test('round-trips MEI by its extension', () {
    final mei = scoreToMei(Score.simple(notes: 'c4:q d4 e4 f4'));
    final score = importScore('tune.mei', _bytes(mei));
    expect(score.measures, isNotEmpty);
  });

  test('is case-insensitive on the extension', () {
    final xml = scoreToMusicXml(Score.simple(notes: 'c4:q d4'));
    expect(importScore('TUNE.MusicXML', _bytes(xml)).measures, isNotEmpty);
  });

  test('rejects an unknown extension with a FormatException', () {
    expect(
      () => importScore('mystery.foo', Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
  });
}
