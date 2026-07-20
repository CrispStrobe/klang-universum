// JAMS chord importer — pure converter (no Flutter). Verifies the Harte→name
// mapping and the JAMS→ChordPro conversion (both data shapes, title, rests,
// error cases), and that the output round-trips through the real ChordPro
// parser + chord→MIDI mapper.

import 'dart:convert';

import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/jams.dart';
import 'package:flutter_test/flutter_test.dart';

String _jams(List<Map<String, Object?>> chordData, {String? title}) =>
    jsonEncode({
      if (title != null) 'file_metadata': {'title': title},
      'annotations': [
        {'namespace': 'chord', 'data': chordData},
      ],
    });

void main() {
  group('harteToChordName', () {
    test('major qualities → plain root triad', () {
      expect(harteToChordName('C:maj'), 'C');
      expect(harteToChordName('C'), 'C'); // bare root = major
      expect(harteToChordName('G:7'), 'G'); // dominant reduces to major triad
      expect(harteToChordName('F#:maj7'), 'F#');
      expect(harteToChordName('Bb:sus4'), 'Bb');
      expect(harteToChordName('D:9'), 'D');
    });

    test('minor / diminished qualities → minor triad', () {
      expect(harteToChordName('A:min'), 'Am');
      expect(harteToChordName('A:min7'), 'Am');
      expect(harteToChordName('E:minmaj7'), 'Em');
      expect(harteToChordName('B:dim'), 'Bm');
      expect(harteToChordName('C#:hdim7'), 'C#m');
    });

    test('slash bass and inversions are dropped', () {
      expect(harteToChordName('C:maj/3'), 'C');
      expect(harteToChordName('A:min7/b7'), 'Am');
      expect(harteToChordName('G:7/5'), 'G');
    });

    test('no-chord and unparseable labels → null', () {
      expect(harteToChordName('N'), isNull);
      expect(harteToChordName('X'), isNull);
      expect(harteToChordName(''), isNull);
      expect(harteToChordName('  '), isNull);
      expect(harteToChordName('foo'), isNull);
    });
  });

  group('jamsToChordPro', () {
    test('converts a chord annotation, keeps title, collapses repeats', () {
      final json = _jams(
        title: 'My Song',
        [
          {'time': 0.0, 'duration': 2.0, 'value': 'C:maj'},
          {'time': 2.0, 'duration': 2.0, 'value': 'C:maj'}, // repeat, collapsed
          {'time': 4.0, 'duration': 2.0, 'value': 'A:min'},
          {'time': 6.0, 'duration': 2.0, 'value': 'F:maj'},
          {'time': 8.0, 'duration': 2.0, 'value': 'G:7'},
        ],
      );
      final cp = jamsToChordPro(json);
      expect(cp, contains('{title: My Song}'));

      final sheet = parseChordPro(cp);
      expect(sheet.title, 'My Song');
      // C (collapsed), Am, F, G — four distinct chords, in order.
      expect(sheet.chords, ['C', 'Am', 'F', 'G']);
      // Every emitted chord is playable (maps to a triad).
      for (final c in sheet.chords) {
        expect(chordMidis(c), isNotNull, reason: c);
      }
    });

    test('a run of N (no chord) breaks the collapse but adds no chip', () {
      final json = _jams([
        {'time': 0.0, 'value': 'C:maj'},
        {'time': 1.0, 'value': 'N'},
        {'time': 2.0, 'value': 'C:maj'}, // same as before, but N broke the run
      ]);
      final cp = jamsToChordPro(json);
      // Two C chips emitted (N broke the collapse); no chip for the N itself.
      expect('[C]'.allMatches(cp).length, 2);
      // The distinct-chord list (a Set) still reports just C.
      expect(parseChordPro(cp).chords, ['C']);
    });

    test('supports the legacy dict-of-arrays data shape', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'chord',
            'data': {
              'time': [0.0, 2.0],
              'value': ['D:maj', 'B:min'],
            },
          },
        ],
      });
      expect(parseChordPro(jamsToChordPro(json)).chords, ['D', 'Bm']);
    });

    test('picks the chord annotation among several namespaces', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'beat',
            'data': [
              {'time': 0.0, 'value': 1},
            ],
          },
          {
            'namespace': 'chord',
            'data': [
              {'time': 0.0, 'value': 'E:maj'},
            ],
          },
        ],
      });
      expect(parseChordPro(jamsToChordPro(json)).chords, ['E']);
    });

    test('throws on non-JSON, non-JAMS, and chord-less inputs', () {
      expect(() => jamsToChordPro('not json'), throwsFormatException);
      expect(() => jamsToChordPro('[1,2,3]'), throwsFormatException);
      expect(
        () => jamsToChordPro(jsonEncode({'annotations': []})),
        throwsFormatException,
      );
      // A chord annotation of only no-chords is still "no usable chords".
      final onlyN = _jams([
        {'time': 0.0, 'value': 'N'},
      ]);
      expect(() => jamsToChordPro(onlyN), throwsFormatException);
    });
  });
}
