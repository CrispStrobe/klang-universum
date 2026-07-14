// Unit tests for importScore — the Workshop's unified, extension-dispatched file
// import. Pure (bytes in, Score out), so it exercises the format routing without
// a file picker.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';
import 'package:klang_universum/features/workshop/screens/composition_workshop_screen.dart';

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

  // ---- importMultiPart (G6): all instrument parts, not just the first ------

  test('importMultiPart keeps both parts of a two-part MusicXML', () {
    const q = NoteDuration(DurationBase.quarter);
    final doc = ScoreDocument()
      ..insertNote(const Pitch(Step.g), q)
      ..insertNote(const Pitch(Step.c, octave: 3), q);
    final xml = grandStaffToMusicXml(doc.buildGrandStaff());
    final mps = importMultiPart('score.musicxml', _bytes(xml));
    expect(mps.parts.length, 2);
  });

  test('importMultiPart wraps a single-part file as one part', () {
    final xml = scoreToMusicXml(Score.simple(notes: 'c4:q d4'));
    final mps = importMultiPart('tune.musicxml', _bytes(xml));
    expect(mps.parts, hasLength(1));
    expect(mps.parts.first.measures, isNotEmpty);
  });

  test('importMultiPart falls back through importScore for unknown types', () {
    expect(
      () => importMultiPart('mystery.foo', Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
  });
}
