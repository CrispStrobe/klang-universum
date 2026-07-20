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
}
