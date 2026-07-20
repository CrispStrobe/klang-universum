// lib/features/games/songs/import/jams.dart
//
// JAMS (JSON Annotated Music Specification, Humphrey et al., ISMIR 2014) import
// + export — the MIR-standard annotation format that ships the big chord/melody/
// beat/key datasets (Isophonics, Billboard, RWC, MedleyDB, …). A JAMS file is
// `{file_metadata, annotations: [{namespace, data: [{time, duration, value,
// confidence}, …]}, …]}`.
//
// This file reads two musical annotations into the app's existing pipelines:
//   • `chord` / `chord_harte` → a ChordPro chord sheet (Harte labels → triads).
//   • `note_midi`             → a melody, rendered to a minimal SMF and fed to
//     the existing MIDI importer. `tempo` sets the SMF tempo (so the rhythm
//     quantizes correctly), `beat` positions infer the time signature, and
//     `key_mode` is surfaced in the title.
//
// It also WRITES JAMS (chordsToJams / notesToJams) so we can produce ground
// truth for automated tests (synthesize → detect → compare against the JAMS).
//
// Pure Dart (no Flutter): unit-testable, and the same converters back the CLI.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/import/chord_quality.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show NoteElement, RestElement, Score;

// ─────────────────────────── decode + shared helpers ────────────────────────

/// Decodes [json] into a JAMS object, or throws [FormatException].
Map<String, dynamic> _decodeJams(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } catch (_) {
    throw const FormatException('Not valid JSON — expected a JAMS file.');
  }
  if (root is! Map<String, dynamic>) {
    throw const FormatException('Not a JAMS object.');
  }
  return root;
}

/// The observations of the first annotation in [root] whose namespace is in
/// [namespaces], normalised to `{time, duration, value}` maps. Handles both the
/// modern list-of-observations and the legacy dict-of-parallel-arrays shapes.
List<Map<String, dynamic>> _observations(
  Map<String, dynamic> root,
  Set<String> namespaces,
) {
  final annotations = root['annotations'];
  if (annotations is! List) return const [];
  for (final a in annotations) {
    if (a is! Map) continue;
    if (!namespaces.contains(a['namespace'])) continue;
    final data = a['data'];
    if (data is List) {
      return [
        for (final o in data)
          if (o is Map) {'value': o['value'], ...o.cast<String, dynamic>()},
      ];
    }
    if (data is Map) {
      final values = data['value'];
      if (values is List) {
        final times = data['time'];
        final durs = data['duration'];
        return [
          for (var i = 0; i < values.length; i++)
            {
              'time': times is List && i < times.length ? times[i] : 0,
              'duration': durs is List && i < durs.length ? durs[i] : 0,
              'value': values[i],
            },
        ];
      }
    }
    return const []; // matched the namespace but data shape is unusable
  }
  return const [];
}

String? _titleOf(Map<String, dynamic> root) {
  final meta = root['file_metadata'];
  if (meta is Map && meta['title'] is String) {
    final t = (meta['title'] as String).trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}

/// The JAMS `file_metadata.title`, or null.
String? jamsTitle(String json) {
  try {
    return _titleOf(_decodeJams(json));
  } catch (_) {
    return null;
  }
}

// ───────────────────────────────── chords ───────────────────────────────────

/// Whether [json] has a chord annotation with at least one real chord.
bool jamsHasChords(String json) {
  try {
    return _chordNames(_decodeJams(json)).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Distinct-run chord names from the first chord annotation (repeats collapsed,
/// a no-chord `N`/`X` breaking the run).
List<String> _chordNames(Map<String, dynamic> root) {
  final out = <String>[];
  String? last;
  for (final o in _observations(root, const {'chord', 'chord_harte'})) {
    final v = o['value'];
    if (v is! String) continue;
    final name = harteToChordName(v);
    if (name == null) {
      last = null;
      continue;
    }
    if (name == last) continue;
    out.add(name);
    last = name;
  }
  return out;
}

/// Converts a JAMS chord annotation into ChordPro source text (reused by the
/// existing chord-sheet pipeline). Throws [FormatException] with no usable
/// chords.
String jamsToChordPro(String json) {
  final root = _decodeJams(json);
  final chords = _chordNames(root);
  if (chords.isEmpty) {
    throw const FormatException('No chord annotation found in the JAMS file.');
  }
  final title = _titleOf(root) ?? 'JAMS chords';
  final buffer = StringBuffer('{title: $title}\n\n');
  for (var i = 0; i < chords.length; i += 4) {
    buffer.writeln(chords.skip(i).take(4).map((c) => '[$c]·').join('  '));
  }
  return buffer.toString();
}

/// Maps a Harte chord [label] to a chord symbol (`C`, `Am`, `G7`, `Cmaj7`,
/// `C#m7b5`), or null for a no-chord / unparseable label. The quality is
/// preserved via the shared vocabulary (7ths, sus, dim/aug, 6ths, 9ths); the
/// slash-bass is dropped and qualities outside the vocabulary reduce to the
/// nearest base quality.
String? harteToChordName(String label) {
  final s = label.trim();
  if (s.isEmpty || s == 'N' || s == 'X') return null;
  final m = RegExp(r'^([A-G][#b]*)').firstMatch(s);
  if (m == null) return null;
  final root = m.group(1)!;
  final colon = s.indexOf(':');
  var quality = '';
  if (colon >= 0) {
    quality = s.substring(colon + 1);
    final slash = quality.indexOf('/');
    if (slash >= 0) quality = quality.substring(0, slash);
    quality = quality.trim();
  }
  return '$root${suffixForHarteQuality(quality)}';
}

// ───────────────────────────────── melody ───────────────────────────────────

/// One note from a `note_midi` annotation.
typedef JamsNote = ({double time, double duration, int midi});

/// The notes of the first `note_midi` annotation in [json], time-sorted.
/// Fractional MIDI values are rounded to the nearest semitone; non-positive
/// durations and out-of-range pitches are skipped.
List<JamsNote> jamsMelodyNotes(String json) {
  final root = _decodeJams(json);
  final out = <JamsNote>[];
  for (final o in _observations(root, const {'note_midi'})) {
    final t = o['time'];
    final d = o['duration'];
    final v = o['value'];
    if (t is! num || v is! num) continue;
    final dur = d is num ? d.toDouble() : 0.0;
    final midi = v.round();
    if (dur <= 0 || midi < 0 || midi > 127) continue;
    out.add((time: t.toDouble(), duration: dur, midi: midi));
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// The tempo (BPM) from the first `tempo` annotation, or null.
double? jamsTempo(String json) {
  try {
    for (final o in _observations(_decodeJams(json), const {'tempo'})) {
      final v = o['value'];
      if (v is num && v > 0) return v.toDouble();
    }
  } catch (_) {}
  return null;
}

/// The time signature (beats per bar + beat unit), or null.
///
/// Prefers the structured **`beat_position`** namespace — its `value` is
/// `{position, measure, num_beats, beat_units}`, so `num_beats`/`beat_units`
/// give a REAL meter and 6/8 ≠ 6/4. Falls back to the scalar **`beat`**
/// namespace (max in-bar position → numerator, assumed `/4`).
({int numerator, int denominator})? jamsMeter(String json) {
  try {
    final root = _decodeJams(json);
    // 1. beat_position: value is a struct carrying the meter directly.
    for (final o in _observations(root, const {'beat_position'})) {
      final v = o['value'];
      if (v is Map && v['num_beats'] is num && (v['num_beats'] as num) >= 2) {
        final n = (v['num_beats'] as num).round();
        final u = v['beat_units'];
        final den = (u is num && u >= 1) ? u.round() : 4;
        return (numerator: n.clamp(2, 32), denominator: _asPowerOfTwo(den));
      }
    }
    // 2. beat: the max in-bar position (scalar, or a {position} struct).
    var maxPos = 0;
    for (final o in _observations(root, const {'beat'})) {
      final v = o['value'];
      if (v is num) {
        maxPos = math.max(maxPos, v.round());
      } else if (v is Map && v['position'] is num) {
        maxPos = math.max(maxPos, (v['position'] as num).round());
      }
    }
    if (maxPos >= 2) return (numerator: maxPos.clamp(2, 32), denominator: 4);
  } catch (_) {}
  return null;
}

/// The beats-per-bar (the meter numerator), or null. See [jamsMeter].
int? jamsBeatsPerBar(String json) => jamsMeter(json)?.numerator;

/// Rounds [n] to the nearest power of two in {1,2,4,8,16,32} (MIDI's
/// time-signature denominator must be a power of two).
int _asPowerOfTwo(int n) {
  const pows = [1, 2, 4, 8, 16, 32];
  var best = 4;
  for (final p in pows) {
    if ((p - n).abs() < (best - n).abs()) best = p;
  }
  return best;
}

/// A human key label ("A minor", "Eb major") from the first `key_mode`
/// annotation, or null. JAMS values look like `C:major`, `Eb:minor`, or `N`.
String? jamsKey(String json) {
  try {
    for (final o in _observations(_decodeJams(json), const {'key_mode'})) {
      final v = o['value'];
      if (v is! String) continue;
      final s = v.trim();
      if (s.isEmpty || s == 'N') continue;
      // Split "TONIC:MODE" (or "TONIC MODE"); default mode = major.
      final sep = s.contains(':') ? ':' : ' ';
      final parts = s.split(sep);
      final tonic = parts.first.trim();
      final mode = parts.length > 1 ? parts[1].trim().toLowerCase() : 'major';
      if (tonic.isEmpty) continue;
      return '$tonic ${mode.isEmpty ? 'major' : mode}';
    }
  } catch (_) {}
  return null;
}

/// Renders the `note_midi` melody of [json] to a minimal Standard MIDI File
/// (format 0), so it can be fed to the app's MIDI importer. The `tempo`
/// annotation (or 120 BPM) drives the seconds→ticks mapping so the rhythm
/// quantizes correctly; a `beat`-derived meter sets the time signature.
///
/// Throws [FormatException] when there is no usable `note_midi` annotation.
Uint8List jamsToMidi(String json) {
  final notes = jamsMelodyNotes(json);
  if (notes.isEmpty) {
    throw const FormatException(
      'No melody (note_midi) annotation found in the JAMS file.',
    );
  }
  const tpq = 480;
  final bpm = jamsTempo(json) ?? 120.0;
  final ticksPerSec = tpq * bpm / 60.0;
  int tick(double sec) => (sec * ticksPerSec).round();

  // (tick, isOn, midi) events; note-offs sort before note-ons at the same tick.
  final events = <(int, bool, int)>[];
  for (final n in notes) {
    final on = tick(n.time);
    final off = math.max(on + 1, tick(n.time + n.duration));
    events.add((on, true, n.midi));
    events.add((off, false, n.midi));
  }
  events.sort((a, b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    return (a.$2 ? 1 : 0).compareTo(b.$2 ? 1 : 0);
  });

  final track = <int>[];
  // Tempo meta (µs per quarter).
  final usPerQuarter = (60000000 / bpm).round();
  track.addAll([
    0x00, 0xFF, 0x51, 0x03, //
    (usPerQuarter >> 16) & 0xFF,
    (usPerQuarter >> 8) & 0xFF,
    usPerQuarter & 0xFF,
  ]);
  // Time-signature meta (nn / 2^dd), inferred from beat_position or beat.
  final meter = jamsMeter(json) ?? (numerator: 4, denominator: 4);
  final dd = (math.log(meter.denominator) / math.ln2).round();
  track.addAll([0x00, 0xFF, 0x58, 0x04, meter.numerator, dd, 24, 8]);

  var cur = 0;
  for (final (t, isOn, m) in events) {
    _writeVlq(track, t - cur);
    cur = t;
    track.addAll(isOn ? [0x90, m, 80] : [0x80, m, 0]);
  }
  track.addAll([0x00, 0xFF, 0x2F, 0x00]); // end of track

  return Uint8List.fromList([
    ...'MThd'.codeUnits,
    0, 0, 0, 6, 0, 0, 0, 1, (tpq >> 8) & 0xFF, tpq & 0xFF, //
    ...'MTrk'.codeUnits,
    (track.length >> 24) & 0xFF,
    (track.length >> 16) & 0xFF,
    (track.length >> 8) & 0xFF,
    track.length & 0xFF,
    ...track,
  ]);
}

/// Appends [value] as a MIDI variable-length quantity to [out].
void _writeVlq(List<int> out, int value) {
  var v = value < 0 ? 0 : value;
  final buf = <int>[v & 0x7F];
  v >>= 7;
  while (v > 0) {
    buf.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.addAll(buf.reversed);
}

// ───────────────────────────── JAMS writers ─────────────────────────────────
// Emit JAMS so tests can generate ground truth (and reader↔writer round-trips).

Map<String, dynamic> _obs(num time, num duration, Object? value) =>
    {'time': time, 'duration': duration, 'value': value, 'confidence': 1.0};

/// A JAMS document (JSON string) with a `chord` annotation for [chords] — one
/// per bar of [barSeconds]. Names are written as Harte labels (`Am` → `A:min`).
String chordsToJams(
  List<String> chords, {
  String? title,
  double barSeconds = 2.0,
}) =>
    jsonEncode({
      if (title != null) 'file_metadata': {'title': title},
      'annotations': [
        {
          'namespace': 'chord',
          'data': [
            for (var i = 0; i < chords.length; i++)
              _obs(i * barSeconds, barSeconds, _nameToHarte(chords[i])),
          ],
        },
      ],
    });

/// Exports [score]'s voice-1 melody as a JAMS `note_midi` document (+ a `tempo`
/// annotation). Onsets/durations are seconds derived from the score's tempo
/// (`quarterBpm`, else 120). Consecutive tied same-pitch notes merge into one
/// observation, so a MIDI→JAMS→MIDI round-trip stays note-stable.
String scoreToJams(Score score, {String? title}) {
  final bpm = score.tempo?.quarterBpm ?? 120.0;
  final secPerQuarter = 60.0 / bpm;

  // Flatten to (startQuarters, durQuarters, midi, tiedForward), advancing a beat
  // cursor over notes AND rests (non-timed elements contribute nothing).
  final raw = <({double start, double dur, int midi, bool tied})>[];
  var cursor = 0.0;
  for (final m in score.measures) {
    for (final e in m.elements) {
      if (e is NoteElement) {
        final (n, d) = e.duration.fraction;
        final q = 4.0 * n / d;
        for (final p in e.pitches) {
          raw.add(
            (start: cursor, dur: q, midi: p.midiNumber, tied: e.tieToNext),
          );
        }
        cursor += q;
      } else if (e is RestElement) {
        final (n, d) = e.duration.fraction;
        cursor += 4.0 * n / d;
      }
    }
  }

  // Merge tied runs (a note tied forward extends into the next same-pitch note).
  final merged = <({double start, double dur, int midi})>[];
  final open = <int, int>{}; // midi → index of the still-open tied note
  for (final r in raw) {
    final at = open[r.midi];
    if (at != null) {
      merged[at] =
          (start: merged[at].start, dur: merged[at].dur + r.dur, midi: r.midi);
      if (!r.tied) open.remove(r.midi);
    } else {
      merged.add((start: r.start, dur: r.dur, midi: r.midi));
      if (r.tied) open[r.midi] = merged.length - 1;
    }
  }

  return notesToJams(
    [
      for (final n in merged)
        (
          time: n.start * secPerQuarter,
          duration: n.dur * secPerQuarter,
          midi: n.midi,
        ),
    ],
    title: title,
    tempo: bpm,
  );
}

/// A JAMS document (JSON string) with a `note_midi` annotation for [notes]
/// (plus an optional `tempo` annotation).
String notesToJams(List<JamsNote> notes, {String? title, double? tempo}) =>
    jsonEncode({
      if (title != null) 'file_metadata': {'title': title},
      'annotations': [
        {
          'namespace': 'note_midi',
          'data': [for (final n in notes) _obs(n.time, n.duration, n.midi)],
        },
        if (tempo != null)
          {
            'namespace': 'tempo',
            'data': [_obs(0, 0, tempo)],
          },
      ],
    });

/// A chord symbol (`Am`, `G7`, `Cmaj7`) → a Harte label (`A:min`, `G:7`,
/// `C:maj7`) — the inverse of [harteToChordName] over the vocabulary.
String _nameToHarte(String name) {
  final sp = splitChordSymbol(name);
  if (sp == null) return 'N';
  return '${sp.root}:${harteQualityForSuffix(sp.suffix)}';
}
