// JAMS chord importer — pure converter (no Flutter). Verifies the Harte→name
// mapping and the JAMS→ChordPro conversion (both data shapes, title, rests,
// error cases), and that the output round-trips through the real ChordPro
// parser + chord→MIDI mapper.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/jams.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show NoteElement, RestElement, scoreFromMidi;
import 'package:flutter_test/flutter_test.dart';

/// The MIDI note numbers of every note in [midi], in order.
List<int> _midiPitches(Uint8List midi) => scoreFromMidi(midi)
    .measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .expand((n) => n.pitches)
    .map((p) => p.midiNumber)
    .toList();

/// A compact `pitch/base` or `R/base` token per element, across all measures —
/// so the quantized rhythm can be asserted directly.
List<String> _elements(Uint8List midi) => [
      for (final m in scoreFromMidi(midi).measures)
        for (final e in m.elements)
          if (e is NoteElement)
            '${e.pitches.map((p) => p.midiNumber).join("+")}/${e.duration.base.name}'
          else if (e is RestElement)
            'R/${e.duration.base.name}',
    ];

String _jams(List<Map<String, Object?>> chordData, {String? title}) =>
    jsonEncode({
      if (title != null) 'file_metadata': {'title': title},
      'annotations': [
        {'namespace': 'chord', 'data': chordData},
      ],
    });

void main() {
  group('harteToChordName', () {
    test('preserves the quality as a chord symbol', () {
      expect(harteToChordName('C:maj'), 'C');
      expect(harteToChordName('C'), 'C'); // bare root = major
      expect(harteToChordName('G:7'), 'G7'); // dominant 7th kept
      expect(harteToChordName('F#:maj7'), 'F#maj7');
      expect(harteToChordName('Bb:sus4'), 'Bbsus4');
      expect(harteToChordName('A:min'), 'Am');
      expect(harteToChordName('A:min7'), 'Am7');
      expect(harteToChordName('E:minmaj7'), 'EmMaj7');
      expect(harteToChordName('B:dim'), 'Bdim');
      expect(harteToChordName('C#:hdim7'), 'C#m7b5');
      expect(harteToChordName('D:min6'), 'Dm6');
      expect(harteToChordName('C:maj9'), 'Cmaj9');
      expect(harteToChordName('A:min9'), 'Am9');
    });

    test('unknown/extended qualities reduce to the nearest base', () {
      // maj13 is beyond the vocabulary → major base (crucially NOT minor).
      expect(harteToChordName('C:maj13'), 'C');
      expect(harteToChordName('C:min11'), 'Cm'); // → minor
      expect(harteToChordName('C:13'), 'C'); // dominant ext → major
      expect(harteToChordName('G:sus4(b7,9)'), 'Gsus4'); // → sus4
    });

    test('slash bass and inversions are dropped (quality kept)', () {
      expect(harteToChordName('C:maj/3'), 'C');
      expect(harteToChordName('A:min7/b7'), 'Am7');
      expect(harteToChordName('G:7/5'), 'G7');
    });

    test('every produced symbol is playable', () {
      for (final l in ['C:maj', 'A:min7', 'G:7', 'F#:maj7', 'C#:hdim7']) {
        expect(chordMidis(harteToChordName(l)!), isNotNull, reason: l);
      }
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
      // C (collapsed), Am, F, G7 — the dominant 7th is preserved.
      expect(sheet.chords, ['C', 'Am', 'F', 'G7']);
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

  group('melody (note_midi)', () {
    String melodyJson(List<Map<String, Object?>> notes, {double? tempo}) =>
        jsonEncode({
          'annotations': [
            {'namespace': 'note_midi', 'data': notes},
            if (tempo != null)
              {
                'namespace': 'tempo',
                'data': [
                  {'time': 0.0, 'duration': 0.0, 'value': tempo},
                ],
              },
          ],
        });

    test('parses, sorts, rounds fractional pitch, skips bad notes', () {
      final json = melodyJson([
        {'time': 1.0, 'duration': 0.5, 'value': 62},
        {'time': 0.0, 'duration': 0.5, 'value': 60.4}, // rounds to 60
        {'time': 2.0, 'duration': 0.0, 'value': 64}, // zero-dur, skipped
        {'time': 3.0, 'duration': 0.5, 'value': 200}, // out of range, skipped
      ]);
      final notes = jamsMelodyNotes(json);
      expect(notes.map((n) => n.midi), [60, 62]); // sorted by time
      expect(notes.first.time, 0.0);
    });

    test('legacy dict-of-arrays note shape', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'note_midi',
            'data': {
              'time': [0.0, 0.5],
              'duration': [0.5, 0.5],
              'value': [60, 67],
            },
          },
        ],
      });
      expect(jamsMelodyNotes(json).map((n) => n.midi), [60, 67]);
    });

    test('jamsToMidi round-trips the pitches through the MIDI reader', () {
      // A C-major scale, one quarter each at 120 BPM (0.5 s/note).
      const scale = [60, 62, 64, 65, 67, 69, 71, 72];
      final json = melodyJson(
        tempo: 120,
        [
          for (var i = 0; i < scale.length; i++)
            {'time': i * 0.5, 'duration': 0.5, 'value': scale[i]},
        ],
      );
      expect(_midiPitches(jamsToMidi(json)), scale);
    });

    test('no note_midi annotation → throws', () {
      expect(() => jamsToMidi('{"annotations":[]}'), throwsFormatException);
    });
  });

  group('tempo / beat / key annotations', () {
    test('jamsTempo reads the BPM', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'tempo',
            'data': [
              {'time': 0.0, 'duration': 0.0, 'value': 96.0},
            ],
          },
        ],
      });
      expect(jamsTempo(json), 96.0);
      expect(jamsTempo('{"annotations":[]}'), isNull);
    });

    test('jamsBeatsPerBar infers the meter from beat positions', () {
      String beats(List<int> positions) => jsonEncode({
            'annotations': [
              {
                'namespace': 'beat',
                'data': [
                  for (var i = 0; i < positions.length; i++)
                    {'time': i * 0.5, 'duration': 0.0, 'value': positions[i]},
                ],
              },
            ],
          });
      expect(jamsBeatsPerBar(beats([1, 2, 3, 1, 2, 3])), 3); // 3/4
      expect(jamsBeatsPerBar(beats([1, 2, 3, 4, 1, 2, 3, 4])), 4); // 4/4
      expect(jamsBeatsPerBar('{"annotations":[]}'), isNull);
    });

    test('jamsMeter reads a structured beat_position (6/8 ≠ 6/4)', () {
      String bp(int numBeats, int beatUnits) => jsonEncode({
            'annotations': [
              {
                'namespace': 'beat_position',
                'data': [
                  {
                    'time': 0.0,
                    'duration': 0.0,
                    'value': {
                      'position': 1,
                      'measure': 0,
                      'num_beats': numBeats,
                      'beat_units': beatUnits,
                    },
                  },
                ],
              },
              {
                'namespace': 'note_midi',
                'data': [
                  {'time': 0.0, 'duration': 0.25, 'value': 60},
                ],
              },
            ],
          });
      // The full meter survives — 6/8 is distinguished from 6/4.
      expect(jamsMeter(bp(6, 8)), (numerator: 6, denominator: 8));
      expect(jamsMeter(bp(6, 4)), (numerator: 6, denominator: 4));
      final ts = scoreFromMidi(jamsToMidi(bp(6, 8))).timeSignature!;
      expect(ts.beats, 6);
      expect(ts.beatUnit, 8);
    });

    test('jamsKey reads TONIC:MODE (and TONIC MODE, and N)', () {
      String key(String v) => jsonEncode({
            'annotations': [
              {
                'namespace': 'key_mode',
                'data': [
                  {'time': 0.0, 'duration': 0.0, 'value': v},
                ],
              },
            ],
          });
      expect(jamsKey(key('A:minor')), 'A minor');
      expect(jamsKey(key('Eb major')), 'Eb major');
      expect(jamsKey(key('C')), 'C major'); // mode defaults to major
      expect(jamsKey(key('N')), isNull);
    });
  });

  group('JAMS writers (ground-truth generation)', () {
    test('chordsToJams → jamsToChordPro round-trips the chords', () {
      final json = chordsToJams(['C', 'Am', 'F', 'G'], title: 'RT');
      expect(jamsTitle(json), 'RT');
      expect(parseChordPro(jamsToChordPro(json)).chords, ['C', 'Am', 'F', 'G']);
    });

    test('notesToJams → jamsMelodyNotes round-trips the notes + tempo', () {
      final notes = <JamsNote>[
        (time: 0.0, duration: 0.5, midi: 60),
        (time: 0.5, duration: 0.5, midi: 64),
        (time: 1.0, duration: 1.0, midi: 67),
      ];
      final json = notesToJams(notes, title: 'Arp', tempo: 100);
      expect(jamsTitle(json), 'Arp');
      expect(jamsTempo(json), 100.0);
      expect(jamsMelodyNotes(json), notes);
    });
  });

  // The hard cases: the notation comes from the (battle-tested) MIDI reader, so
  // these lock the seconds→ticks mapping that feeds it.
  group('melody rhythm & edge cases (quantization)', () {
    test('mixed durations quantize to the right note values', () {
      // eighth(0.25) quarter(0.5) half(1.0) at 120 BPM, packed into one bar.
      final json = notesToJams(tempo: 120, const [
        (time: 0.0, duration: 0.25, midi: 60),
        (time: 0.25, duration: 0.5, midi: 62),
        (time: 0.75, duration: 1.0, midi: 64),
      ]);
      final e = _elements(jamsToMidi(json));
      expect(e, ['60/eighth', '62/quarter', '64/half']);
    });

    test('a leading offset becomes a rest', () {
      // First note at 0.5 s (a quarter's silence) at 120 BPM.
      final json = notesToJams(tempo: 120, const [
        (time: 0.5, duration: 0.5, midi: 60),
        (time: 1.0, duration: 0.5, midi: 62),
      ]);
      final e = _elements(jamsToMidi(json));
      expect(e.first, 'R/quarter');
      expect(e.where((x) => x.startsWith('60')), isNotEmpty);
    });

    test('a mid-melody gap becomes a rest', () {
      // A note, a beat of silence, a note — at 120 BPM.
      final json = notesToJams(tempo: 120, const [
        (time: 0.0, duration: 0.5, midi: 60),
        (time: 1.0, duration: 0.5, midi: 67),
      ]);
      final e = _elements(jamsToMidi(json));
      expect(e, containsAllInOrder(['60/quarter', 'R/quarter', '67/quarter']));
    });

    test('tempo changes the quantized rhythm (same seconds)', () {
      List<JamsNote> half() => const [(time: 0.0, duration: 0.5, midi: 60)];
      // 0.5 s is an eighth at 60 BPM (beat = 1 s) but a quarter at 120 BPM.
      final slow = _elements(jamsToMidi(notesToJams(tempo: 60, half())));
      final fast = _elements(jamsToMidi(notesToJams(tempo: 120, half())));
      expect(slow, ['60/eighth']);
      expect(fast, ['60/quarter']);
    });

    test('a beat annotation sets the time signature', () {
      const json = '{"annotations":['
          '{"namespace":"note_midi","data":['
          '{"time":0.0,"duration":0.5,"value":60}]},'
          '{"namespace":"beat","data":['
          '{"time":0.0,"value":1},{"time":0.5,"value":2},'
          '{"time":1.0,"value":3},{"time":1.5,"value":1}]},'
          '{"namespace":"tempo","data":[{"time":0.0,"value":120}]}]}';
      expect(scoreFromMidi(jamsToMidi(json)).timeSignature!.beats, 3);
    });

    test('a note far into the piece round-trips (multi-byte VLQ delta)', () {
      // 30 s in at 120 BPM = 57600 ticks → a 3-byte variable-length quantity.
      final json = notesToJams(tempo: 120, const [
        (time: 0.0, duration: 0.5, midi: 60),
        (time: 30.0, duration: 0.5, midi: 72),
      ]);
      final pitches = _midiPitches(jamsToMidi(json));
      expect(pitches.first, 60);
      expect(pitches.last, 72);
    });

    test('malformed / partial observations are skipped, not fatal', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'note_midi',
            'data': [
              {'time': 0.0, 'duration': 0.5, 'value': 60},
              {'time': 0.5, 'duration': 0.5}, // no value
              {'time': null, 'duration': 0.5, 'value': 62}, // no time
              {'time': 1.0, 'duration': 0.5, 'value': 'x'}, // non-numeric
              {'time': 1.5, 'duration': 0.5, 'value': 64},
            ],
          },
        ],
      });
      expect(jamsMelodyNotes(json).map((n) => n.midi), [60, 64]);
    });
  });

  group('annotation selection', () {
    test('melody wins when a file carries both chords and notes', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'chord',
            'data': [
              {'time': 0.0, 'duration': 2.0, 'value': 'C:maj'},
            ],
          },
          {
            'namespace': 'note_midi',
            'data': [
              {'time': 0.0, 'duration': 0.5, 'value': 60},
            ],
          },
        ],
      });
      // Both are present; the import screen prefers the (richer) melody.
      expect(jamsMelodyNotes(json), isNotEmpty);
      expect(jamsHasChords(json), isTrue);
    });

    test('the strict chord_harte namespace is accepted', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'chord_harte',
            'data': [
              {'time': 0.0, 'duration': 2.0, 'value': 'D:min7'},
              {'time': 2.0, 'duration': 2.0, 'value': 'G:7'},
              {'time': 4.0, 'duration': 2.0, 'value': 'C:maj7'},
            ],
          },
        ],
      });
      final chords = parseChordPro(jamsToChordPro(json)).chords;
      expect(chords, ['Dm7', 'G7', 'Cmaj7']);
    });
  });

  group('chord round-trip (Harte ↔ symbol) is lossless for the vocabulary', () {
    test('chordsToJams → jamsToChordPro preserves the qualities', () {
      const chords = ['C', 'Am7', 'Dm7', 'G7', 'Cmaj7', 'F#m7b5', 'Bdim'];
      final json = chordsToJams(chords);
      expect(parseChordPro(jamsToChordPro(json)).chords, chords);
    });
  });

  group('scoreToJams export + MIDI round-trip', () {
    test('a melody survives MIDI → JAMS → MIDI note-for-note', () {
      const scale = [60, 62, 64, 65, 67, 69];
      // The "original" MIDI, authored via JAMS.
      final midi1 = jamsToMidi(
        notesToJams(
          [
            for (var i = 0; i < scale.length; i++)
              (time: i * 0.5, duration: 0.5, midi: scale[i]),
          ],
          tempo: 120,
        ),
      );
      // Read → export → re-import: EXPORT is the new scoreToJams.
      final exported = scoreToJams(scoreFromMidi(midi1), title: 'rt');
      expect(jamsTitle(exported), 'rt');
      final midi2 = jamsToMidi(exported);
      expect(_midiPitches(midi2), _midiPitches(midi1));
      expect(_midiPitches(midi2), scale);
    });

    test('scoreToJams merges tied notes into one observation', () {
      // A note that crosses a barline is engraved as two tied notes; the export
      // must emit ONE note_midi observation, not two.
      final tied = jamsToMidi(
        notesToJams(
          const [
            // A dotted-half at beat 3 of 4/4 spills into the next bar → tie.
            (time: 0.0, duration: 1.0, midi: 60),
            (time: 0.5 * 3, duration: 1.5, midi: 67),
          ],
          tempo: 120,
        ),
      );
      final notes = jamsMelodyNotes(scoreToJams(scoreFromMidi(tied)));
      // Two distinct pitches, not three (the tie did not split into two obs).
      expect(notes.map((n) => n.midi), [60, 67]);
    });
  });

  group('ChoCo compatibility', () {
    String jamsWith(String ns, List<String> labels) => jsonEncode({
          'file_metadata': {'title': 'x'},
          'annotations': [
            {
              'namespace': ns,
              'data': [
                for (var i = 0; i < labels.length; i++)
                  {'time': i * 1.0, 'duration': 1.0, 'value': labels[i]},
              ],
            },
          ],
        });

    for (final ns in [
      'chord_m21_leadsheet',
      'chord_m21_abc',
      'chord_weimar',
      'chord_jparser_functional',
    ]) {
      test('reads the $ns namespace', () {
        expect(jamsHasChords(jamsWith(ns, ['C:maj', 'A:min7'])), isTrue);
        expect(
          jamsToChordPro(jamsWith(ns, ['C:maj', 'A:min7'])),
          allOf(contains('[C]'), contains('[Am7]')),
        );
      });
    }

    test('non-Harte shorthand is rejected, never degraded to a wrong chord',
        () {
      // Regression: these used to silently become the bare root, so a minor
      // chord imported as MAJOR and sevenths vanished — a wrong import that
      // looked successful.
      for (final bad in ['C-7', 'C#m', 'Cmaj7', 'C7', 'Bbm']) {
        expect(harteToChordName(bad), isNull, reason: '$bad is not Harte');
      }
      // Real Harte still parses, with quality preserved.
      expect(harteToChordName('C:maj'), 'C');
      expect(harteToChordName('A:min7'), 'Am7');
      expect(harteToChordName('G:7/3'), 'G7');
      // A bare root IS valid Harte (= major).
      expect(harteToChordName('C'), 'C');
      expect(harteToChordName('Bb'), 'Bb');
    });

    test('weimar jazz shorthand is now parsed in its own dialect', () {
      // Was: "yields no chords rather than wrong ones". The dialect is now
      // implemented, so these read correctly instead of being skipped.
      expect(jamsHasChords(jamsWith('chord_weimar', ['C-7', 'F-7'])), isTrue);
      expect(
        jamsToChordPro(jamsWith('chord_weimar', ['C-7', 'F-7'])),
        allOf(contains('[Cm7]'), contains('[Fm7]')),
      );
    });

    test('an unrecognised quality is still skipped, not degraded', () {
      // The dialects widen what we understand; they do NOT weaken the rule
      // that an unknown quality must never fall back to a bare major triad.
      expect(jamsHasChords(jamsWith('chord_weimar', ['Cqqq', 'Fzz'])), isFalse);
    });

    test('malformed weimar key_mode ("Bb-maj") parses', () {
      String keyJams(String v) => jsonEncode({
            'annotations': [
              {
                'namespace': 'key_mode',
                'data': [
                  {'time': 0.0, 'duration': 0.0, 'value': v},
                ],
              },
            ],
          });
      expect(jamsKey(keyJams('Bb-maj')), 'Bb major');
      expect(jamsKey(keyJams('A-min')), 'A minor');
      // The well-formed spelling is unaffected.
      expect(jamsKey(keyJams('Eb:minor')), 'Eb minor');
      expect(jamsKey(keyJams('C:major')), 'C major');
    });
  });

  group('non-finite JSON literals (Python interop)', () {
    // Python's json.dump writes bare NaN/Infinity by default. Dart rejects
    // those per RFC 8259, so 2 of ChoCo's 17,797 files failed to open at all
    // with a message that blamed the file for being "not valid JSON".
    String jamsWithLiteral(String literal) => '''
{
  "file_metadata": {"title": "x", "duration": $literal},
  "annotations": [
    {"namespace": "chord",
     "data": [{"time": 0.0, "duration": 1.0, "value": "C:maj",
               "confidence": $literal}]}
  ]
}''';

    for (final literal in ['NaN', 'Infinity', '-Infinity']) {
      test('a bare $literal no longer fails the whole file', () {
        final json = jamsWithLiteral(literal);
        expect(jamsHasChords(json), isTrue);
        expect(jamsToChordPro(json), contains('[C]'));
        expect(jamsTitle(json), 'x');
      });
    }

    test('"Infinity" as a STRING value is left intact', () {
      // ChoCo's weimar_302 has "release": "Infinity" — an album name. Nulling
      // that would corrupt the metadata, so only bare literals are patched.
      const json = '{"file_metadata": {"title": "Infinity"}, '
          '"annotations": [{"namespace": "chord", "data": '
          '[{"time": 0.0, "duration": 1.0, "value": "C:maj"}]}]}';
      expect(jamsTitle(json), 'Infinity');
      expect(jamsHasChords(json), isTrue);
    });

    test('an escaped quote before a literal does not desync the scanner', () {
      const json = r'{"file_metadata": {"title": "say \"NaN\" twice"}, '
          '"annotations": [{"namespace": "chord", "data": '
          '[{"time": 0.0, "duration": 1.0, "value": "C:maj"}]}]}';
      expect(jamsTitle(json), r'say "NaN" twice');
      expect(jamsHasChords(json), isTrue);
    });

    test('genuinely broken JSON still throws', () {
      expect(() => jamsToChordPro('{not json'), throwsFormatException);
    });
  });

  group('shorthand dialects (music21 vs jazz)', () {
    test('THE conflict: `-` is a flat in music21, a minor in jazz', () {
      // Same three characters, different chords. Reading either file with the
      // other dialect's parser silently produces a wrong chord — which is why
      // the namespace, not the label, selects the parser.
      expect(music21ChordToName('B-'), 'Bb'); // B FLAT major
      expect(jazzChordToName('B-'), 'Bm'); // B MINOR
      expect(music21ChordToName('B-7'), 'Bb7');
      expect(jazzChordToName('B-7'), 'Bm7');
    });

    test('music21 spellings (wikifonia, nottingham)', () {
      expect(music21ChordToName('C'), 'C');
      expect(music21ChordToName('E-'), 'Eb');
      expect(music21ChordToName('Am'), 'Am');
      expect(music21ChordToName('Dm7'), 'Dm7');
      expect(music21ChordToName('F#m'), 'F#m');
      expect(music21ChordToName('G7'), 'G7');
      expect(music21ChordToName('Cmaj7'), 'Cmaj7');
      expect(music21ChordToName('C/E'), 'C'); // slash bass dropped
    });

    test('jazz spellings (weimar, jazz-corpus)', () {
      expect(jazzChordToName('Bb7'), 'Bb7');
      expect(jazzChordToName('C-7'), 'Cm7');
      expect(jazzChordToName('Ebj7'), 'Ebmaj7'); // j = major 7th
      expect(jazzChordToName('CM7'), 'Cmaj7'); // M = major 7th
      expect(jazzChordToName('Co7'), 'Cdim7');
      expect(jazzChordToName('C+'), 'Caug');
      expect(jazzChordToName('Cø'), 'Cm7b5');
      expect(jazzChordToName('Csus'), 'Csus4');
    });

    test('longest-prefix wins, so m7b5 never reads as m7 or m', () {
      expect(jazzChordToName('Cm7b5'), 'Cm7b5');
      expect(jazzChordToName('Cm7'), 'Cm7');
      expect(jazzChordToName('Cm'), 'Cm');
      expect(jazzChordToName('CmMaj7'), 'CmMaj7');
    });

    test('alterations reduce to the base quality, as Harte extensions do', () {
      expect(jazzChordToName('C7(b9)'), 'C7');
      expect(jazzChordToName('C13'), 'C7');
      expect(music21ChordToName('C11'), 'C7');
    });

    test('a Harte label is read as Harte in any dialect', () {
      // ChoCo mixes true Harte labels into the parser-named partitions; `:` is
      // unambiguous, so it always wins over the dialect.
      expect(music21ChordToName('C:maj'), 'C');
      expect(jazzChordToName('A:min7'), 'Am7');
    });

    test('no-chord markers and unknown qualities yield null', () {
      expect(music21ChordToName('N'), isNull);
      expect(jazzChordToName('X'), isNull);
      expect(jazzChordToName('NC'), isNull); // weimar's no-chord spelling
      expect(jazzChordToName('Cqqq'), isNull);
      expect(music21ChordToName('Hm'), isNull);
      expect(jazzChordToName(42), isNull);
    });

    test('a raw pitch list is not mistaken for a chord', () {
      // 54 wikifonia files carry note collections (`B4,G4,E4`) instead of
      // chord symbols; those must read as nothing, not as B major.
      expect(music21ChordToName('B4,G4,E4'), isNull);
      expect(music21ChordToName('B-3,D5'), isNull);
    });

    test('functional degrees resolve against their key', () {
      expect(functionalChordToName('C major:Ton'), 'C');
      expect(functionalChordToName('C major:Sub'), 'F');
      expect(functionalChordToName('C major:Dom'), 'G');
      expect(functionalChordToName('Bb major:Dom'), 'F');
      // A non-functional value in this namespace is ordinary Harte.
      expect(functionalChordToName('C:maj'), 'C');
      expect(functionalChordToName('N'), isNull);
    });
  });

  group('chord_roman (rock-corpus / when-in-rome / mozart)', () {
    test('reads a key-relative numeral against a major key', () {
      expect(romanChordToName('C:I'), 'C');
      expect(romanChordToName('C:ii'), 'Dm');
      expect(romanChordToName('C:V'), 'G');
      expect(romanChordToName('C:vi'), 'Am');
    });

    test('the key transposes the numeral', () {
      expect(romanChordToName('Bb major:ii65'), 'Cm');
      expect(romanChordToName('Bb major:vi64'), 'Gm');
      expect(romanChordToName('F:I64'), 'F');
      expect(romanChordToName('F:V11'), 'C');
    });

    test('a minor key reads its degrees off the natural-minor scale', () {
      // III is Eb in C minor but E in C major — the offset table must follow
      // the KEY, not the numeral's case.
      expect(romanChordToName('C minor:III'), 'Eb');
      expect(romanChordToName('C major:III'), 'E');
      expect(romanChordToName('C minor:i'), 'Cm');
      expect(romanChordToName('C minor:VI'), 'Ab');
    });

    test('accidentals shift the degree, and spell flat', () {
      expect(romanChordToName('C:bIII'), 'Eb');
      expect(romanChordToName('C:bVII'), 'Bb');
      expect(romanChordToName('C:#iv'), 'F#m');
    });

    test('quality marks beat the numeral case', () {
      expect(romanChordToName('C:viio'), 'Bdim');
      expect(romanChordToName('C:viiø7'), 'Bm7b5');
      expect(romanChordToName('C:V+'), 'Gaug');
    });

    test('figures are dropped — a triad, never a guessed seventh', () {
      // V7 is dominant, IV7 is major, ii7 is minor: resolving the figure needs
      // diatonic context, so we deliberately keep the triad.
      expect(romanChordToName('C:V7'), 'G');
      expect(romanChordToName('C:I64'), 'C');
      expect(romanChordToName('C:ii43'), 'Dm');
    });

    test('the stock JAMS struct shape is read too', () {
      expect(romanChordToName({'tonic': 'C', 'chord': 'V'}), 'G');
      expect(romanChordToName({'tonic': 'Bb', 'chord': 'ii'}), 'Cm');
    });

    test('unresolvable or no-chord labels yield null', () {
      expect(romanChordToName('N'), isNull);
      expect(romanChordToName('X'), isNull);
      expect(romanChordToName('I'), isNull, reason: 'no key — unresolvable');
      expect(romanChordToName('C:xyz'), isNull);
      expect(romanChordToName('H:I'), isNull);
      expect(romanChordToName(42), isNull);
    });

    test('a chord_roman file converts to a chord sheet', () {
      final json = jsonEncode({
        'file_metadata': {'title': 'roman'},
        'annotations': [
          {
            'namespace': 'chord_roman',
            'data': [
              for (final (i, v)
                  in ['C:I', 'C:I', 'C:IV', 'C:V', 'N', 'C:I'].indexed)
                {'time': i * 1.0, 'duration': 1.0, 'value': v},
            ],
          },
        ],
      });
      expect(jamsHasChords(json), isTrue);
      final cp = jamsToChordPro(json);
      // Repeats collapse; the rest breaks the run so the final C returns.
      expect(cp, allOf(contains('[C]'), contains('[F]'), contains('[G]')));
      expect('[C]'.allMatches(cp).length, 2);
    });

    test('Harte wins when a file carries both', () {
      final json = jsonEncode({
        'annotations': [
          {
            'namespace': 'chord',
            'data': [
              {'time': 0.0, 'duration': 1.0, 'value': 'A:min'},
            ],
          },
          {
            'namespace': 'chord_roman',
            'data': [
              {'time': 0.0, 'duration': 1.0, 'value': 'C:V'},
            ],
          },
        ],
      });
      expect(jamsToChordPro(json), contains('[Am]'));
      expect(jamsToChordPro(json), isNot(contains('[G]')));
    });
  });
}
