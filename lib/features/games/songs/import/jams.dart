// lib/features/games/songs/import/jams.dart
//
// JAMS (JSON Annotated Music Specification, Humphrey et al., ISMIR 2014) import
// + export — the MIR-standard annotation format that ships the big chord/melody/
// beat/key datasets (Isophonics, Billboard, RWC, MedleyDB, …). A JAMS file is
// `{file_metadata, annotations: [{namespace, data: [{time, duration, value,
// confidence}, …]}, …]}`.
//
// This file reads two musical annotations into the app's existing pipelines:
//   • chord annotations → a ChordPro chord sheet. Each namespace is written in
//     a known label DIALECT, and the namespace selects the parser: Harte
//     ([harteToChordName]), music21 ([music21ChordToName]), jazz shorthand
//     ([jazzChordToName]), functional degrees ([functionalChordToName]) and
//     key-relative roman numerals ([romanChordToName]). Within a dialect an
//     unrecognised quality is skipped, never guessed at.
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
  Object? root;
  try {
    root = jsonDecode(json);
  } catch (_) {
    // Python's `json.dump` emits bare NaN/Infinity by default — non-standard
    // JSON, which Dart rightly rejects (RFC 8259). But Python IS the JAMS
    // toolchain, so real corpus files carry them (2 of ChoCo's 17,797). Retry
    // once with those literals nulled out rather than failing the whole file.
    final patched = _nullifyNonFiniteLiterals(json);
    try {
      root = patched == null ? null : jsonDecode(patched);
    } catch (_) {
      root = null;
    }
    if (root == null) {
      throw const FormatException('Not valid JSON — expected a JAMS file.');
    }
  }
  if (root is! Map<String, dynamic>) {
    throw const FormatException('Not a JAMS object.');
  }
  return root;
}

/// Replaces bare `NaN` / `Infinity` / `-Infinity` literals with `null`, leaving
/// string CONTENTS untouched — an album really can be called "Infinity"
/// (ChoCo's `weimar_302`), and rewriting that would corrupt the metadata.
/// Returns null when there was nothing to patch, so we don't re-parse for free.
String? _nullifyNonFiniteLiterals(String json) {
  final out = StringBuffer();
  var changed = false;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < json.length; i++) {
    final c = json[i];
    if (inString) {
      out.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      continue;
    }
    const tokens = ['-Infinity', 'Infinity', 'NaN'];
    var matched = false;
    for (final t in tokens) {
      if (json.startsWith(t, i)) {
        out.write('null');
        i += t.length - 1;
        changed = matched = true;
        break;
      }
    }
    if (!matched) out.write(c);
  }
  return changed ? out.toString() : null;
}

/// The observations of the first annotation in [root] whose namespace is in
/// [namespaces], normalised to `{time, duration, value}` maps. Handles both the
/// modern list-of-observations and the legacy dict-of-parallel-arrays shapes.
List<Map<String, dynamic>> _observations(
  Map<String, dynamic> root,
  Set<String> namespaces, {
  Set<String> prefixes = const {},
}) {
  final annotations = root['annotations'];
  if (annotations is! List) return const [];
  for (final a in annotations) {
    if (a is! Map) continue;
    final ns = a['namespace'];
    final hit = namespaces.contains(ns) ||
        (ns is String && prefixes.any(ns.startsWith));
    if (!hit) continue;
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

// A namespace name says which PARSER produced the file, and therefore which
// label dialect it is written in. That is the only safe disambiguator, because
// the dialects genuinely conflict:
//
//   ⚠ `-` means FLAT in music21 (`B-` = B♭, 12,021 uses in ChoCo's wikifonia)
//     but MINOR in jazz shorthand (`C-7` = Cm7, 1,143 uses in weimar).
//
// The same three characters mean different chords depending on the partition,
// so each dialect gets its OWN parser and they are never mixed. A label
// containing `:` is unambiguously Harte and is read as Harte in any dialect.

/// The JAMS standard chord namespaces (Harte labels).
const Set<String> kChordNamespaces = {'chord', 'chord_harte'};

/// music21-spelled leadsheet partitions — wikifonia, nottingham. `-` = flat.
const Set<String> kMusic21ChordNamespaces = {
  'chord_m21_leadsheet',
  'chord_m21_abc',
};

/// Jazz-shorthand partitions — weimar, jazz-corpus. `-` = minor, `j` = maj7.
const Set<String> kJazzChordNamespaces = {
  'chord_weimar',
  'chord_jparser_harte',
};

/// Functional-degree partitions — jazz-corpus's `<key>:Ton|Sub|Dom`.
const Set<String> kFunctionalChordNamespaces = {'chord_jparser_functional'};

/// Namespace prefixes matched loosely — ChoCo's `chord_jparser_*` family.
const Set<String> kChordNamespacePrefixes = {'chord_jparser'};

/// Roman-numeral chord namespaces. These carry no Harte labels at all, so they
/// are read only as a FALLBACK — a file with both keeps its Harte reading.
const Set<String> kRomanChordNamespaces = {'chord_roman'};

/// Whether [json] has a chord annotation with at least one real chord.
bool jamsHasChords(String json) {
  try {
    return _chordNames(_decodeJams(json)).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// One label dialect: the namespaces written in it, and how to read a label.
typedef _ChordDialect = ({
  Set<String> namespaces,
  String? Function(Object? value) parse,
});

/// Tried in order; the first dialect that yields any chord wins. Harte leads so
/// a file carrying both a standard and a derived annotation keeps the standard.
final List<_ChordDialect> _chordDialects = [
  (
    namespaces: kChordNamespaces,
    parse: (v) => v is String ? harteToChordName(v) : null,
  ),
  (namespaces: kMusic21ChordNamespaces, parse: music21ChordToName),
  (namespaces: kJazzChordNamespaces, parse: jazzChordToName),
  (namespaces: kFunctionalChordNamespaces, parse: functionalChordToName),
  (namespaces: kRomanChordNamespaces, parse: romanChordToName),
];

/// Distinct-run chord names from the first chord annotation (repeats collapsed,
/// a no-chord `N`/`X` breaking the run).
List<String> _chordNames(Map<String, dynamic> root) {
  for (final dialect in _chordDialects) {
    final names = _collapseRuns(
      _observations(root, dialect.namespaces),
      dialect.parse,
    );
    if (names.isNotEmpty) return names;
  }
  return const [];
}

/// Maps each observation through [name] and collapses consecutive repeats; a
/// null (no-chord / unparseable) breaks the run.
List<String> _collapseRuns(
  List<Map<String, dynamic>> observations,
  String? Function(Object? value) name,
) {
  final out = <String>[];
  String? last;
  for (final o in observations) {
    final n = name(o['value']);
    if (n == null) {
      last = null;
      continue;
    }
    if (n == last) continue;
    out.add(n);
    last = n;
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

  // Harte is `root[:quality][/bass]`. Anything else after the root — jazz or
  // music21 shorthand like `C-7`, `Cmaj7`, `C#m` — is NOT Harte, and must be
  // rejected rather than parsed. Silently keeping just the root turned `C-7`
  // into C major and `C#m` into C#: a wrong chord that looks like a successful
  // import. Callers skip a null, which is the honest outcome.
  final rest = s.substring(root.length);
  if (rest.isNotEmpty && !rest.startsWith(':') && !rest.startsWith('/')) {
    return null;
  }

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

// ──────────────────────────── shorthand dialects ────────────────────────────
// music21 and jazz lead-sheet spellings. Both are `root + quality [/bass]`;
// they differ ONLY in how the root is spelled (see the `-` warning above), so
// the quality vocabulary below is shared.

/// Shorthand quality → the app's display suffix. Matched longest-prefix-first,
/// so `m7b5` wins over `m7` wins over `m`. An unrecognised quality yields null
/// (the chord is skipped) rather than silently degrading to the bare root.
const Map<String, String> _shorthandQualities = {
  // sevenths and their major/minor variants
  'minmaj7': 'mMaj7', 'mMaj7': 'mMaj7', 'mM7': 'mMaj7', '-j7': 'mMaj7',
  'min7b5': 'm7b5', 'm7b5': 'm7b5', '-7b5': 'm7b5', 'hdim7': 'm7b5',
  'ø7': 'm7b5', 'ø': 'm7b5',
  'maj7': 'maj7', 'Maj7': 'maj7', 'M7': 'maj7', 'j7': 'maj7', 'Δ7': 'maj7',
  'Δ': 'maj7', '^7': 'maj7',
  'min7': 'm7', 'm7': 'm7', '-7': 'm7',
  'dim7': 'dim7', 'o7': 'dim7', '°7': 'dim7',
  // triads
  'dim': 'dim', 'o': 'dim', '°': 'dim',
  'aug': 'aug', '+': 'aug', '#5': 'aug', '+5': 'aug',
  'sus2': 'sus2', 'sus4': 'sus4', 'sus': 'sus4',
  // sixths, ninths, adds
  'maj9': 'maj9', 'M9': 'maj9', 'j9': 'maj9',
  'min9': 'm9', 'm9': 'm9', '-9': 'm9',
  'min6': 'm6', 'm6': 'm6', '-6': 'm6',
  'add9': 'add9',
  '6': '6', '9': '9', '7': '7',
  // plain triads, and dominant extensions that reduce to their base
  'maj': '', 'major': '', 'M': '',
  'min': 'm', 'minor': 'm', 'm': 'm', '-': 'm',
  '11': '7', '13': '7',
};

/// Keys longest-first, so a prefix match never shadows a longer quality.
final List<String> _shorthandQualityKeys = _shorthandQualities.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));

/// The display suffix for a shorthand [quality], or null if unrecognised.
String? _suffixForShorthand(String quality) {
  final q = quality.trim();
  if (q.isEmpty) return ''; // bare root = major
  for (final k in _shorthandQualityKeys) {
    // A recognised prefix fixes the base quality; trailing alterations
    // (`7(b9)`, `13#11`) reduce to it, exactly as Harte extensions do.
    if (q.startsWith(k)) return _shorthandQualities[k];
  }
  return null;
}

/// Strips a slash-bass and any parenthesised alteration from a shorthand label.
String _stripShorthandTail(String s) {
  var out = s;
  final slash = out.indexOf('/');
  if (slash >= 0) out = out.substring(0, slash);
  final paren = out.indexOf('(');
  if (paren >= 0) out = out.substring(0, paren);
  return out.trim();
}

/// Reads a **music21**-spelled label (`C`, `B-`, `B-7`, `Dm7`, `F#m`, `C/E`).
/// ⚠ `-` is a FLAT here, never a minor.
String? music21ChordToName(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  if (s.isEmpty || s == 'N' || s == 'X' || s == 'NC') return null;
  if (s.contains(':')) return harteToChordName(s); // unambiguously Harte
  final m = RegExp(r'^([A-G][#\-b]*)').firstMatch(s);
  if (m == null) return null;
  final rawRoot = m.group(1)!;
  final root = rawRoot.replaceAll('-', 'b'); // music21 flat → our spelling
  final suffix = _suffixForShorthand(
    _stripShorthandTail(s.substring(rawRoot.length)),
  );
  return suffix == null ? null : '$root$suffix';
}

/// Reads a **jazz**-shorthand label (`C-7`, `Bb7`, `Ebj7`, `CM7`, `Co7`).
/// ⚠ `-` is a MINOR here, never a flat; flats are spelled `b`.
String? jazzChordToName(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  // `NC` is Weimar's no-chord marker (its unaccompanied solos).
  if (s.isEmpty || s == 'N' || s == 'X' || s == 'NC') return null;
  if (s.contains(':')) return harteToChordName(s); // unambiguously Harte
  final m = RegExp(r'^([A-G][#b]*)').firstMatch(s);
  if (m == null) return null;
  final root = m.group(1)!;
  final suffix = _suffixForShorthand(
    _stripShorthandTail(s.substring(root.length)),
  );
  return suffix == null ? null : '$root$suffix';
}

/// Reads a functional-degree label (`F major:Dom` → C). Tonic/subdominant/
/// dominant are the I/IV/V of the stated key, so this reuses the roman reader.
const Map<String, String> _functionalDegrees = {
  'ton': 'I',
  'sub': 'IV',
  'dom': 'V',
};

String? functionalChordToName(Object? value) {
  if (value is! String) return null;
  final s = value.trim();
  if (s.isEmpty || s == 'N' || s == 'X') return null;
  final colon = s.indexOf(':');
  if (colon < 0) return null;
  final numeral =
      _functionalDegrees[s.substring(colon + 1).trim().toLowerCase()];
  // `<key>:<function>` is this namespace's own dialect; anything else after the
  // colon is an ordinary Harte quality (`C:maj`), which ChoCo also emits here.
  if (numeral == null) return harteToChordName(s);
  return _romanToName(s.substring(0, colon).trim(), numeral);
}

// ────────────────────────── roman-numeral chords ────────────────────────────
// `chord_roman` is key-relative: the label only means something once you know
// the tonic, so each observation carries its own key. ChoCo writes it as the
// STRING `"<key>:<numeral>"` (`"F:I64"`, `"Bb major:ii65"`, `"C:I"`); stock
// JAMS uses a struct with `tonic`/`chord` keys. Both are read.
//
// ⚠ TRIADS ONLY, by design. A figure (`64`, `7`, `65`, `11`) marks inversion
// and extension, and turning it into a seventh needs the diatonic context —
// `V7` is dominant, `IV7` is major, `ii7` is minor, and a chromatic alteration
// changes all three. Guessing would produce confident-looking wrong chords, so
// figures are dropped and only the triad quality is kept. That matches
// [harteToChordName]'s rule: reject rather than guess.

/// Scale-degree semitone offsets — the numeral is read against the KEY's own
/// scale, so `III` is E in C major but Eb in C minor.
const List<int> _majorDegreeOffsets = [0, 2, 4, 5, 7, 9, 11];
const List<int> _minorDegreeOffsets = [0, 2, 3, 5, 7, 8, 10];

const Map<String, int> _romanDegrees = {
  'i': 1,
  'ii': 2,
  'iii': 3,
  'iv': 4,
  'v': 5,
  'vi': 6,
  'vii': 7,
};

const List<String> _sharpSpelling = [
  'C', 'C#', 'D', 'D#', 'E', 'F', //
  'F#', 'G', 'G#', 'A', 'A#', 'B',
];
const List<String> _flatSpelling = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', //
  'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
];
const Map<String, int> _naturalPitchClasses = {
  'C': 0,
  'D': 2,
  'E': 4,
  'F': 5,
  'G': 7,
  'A': 9,
  'B': 11,
};

/// Converts one `chord_roman` [value] to a chord symbol (`F`, `Cm`, `Bdim`), or
/// null for a no-chord / unparseable label.
String? romanChordToName(Object? value) {
  final String key;
  final String numeral;
  if (value is Map) {
    final t = value['tonic'];
    final c = value['chord'];
    if (t is! String || c is! String) return null;
    key = t;
    numeral = c;
  } else if (value is String) {
    final s = value.trim();
    if (s.isEmpty || s == 'N' || s == 'X') return null;
    final colon = s.indexOf(':');
    if (colon < 0) return null; // key-less numeral is unresolvable
    key = s.substring(0, colon);
    numeral = s.substring(colon + 1);
  } else {
    return null;
  }
  return _romanToName(key.trim(), numeral.trim());
}

String? _romanToName(String key, String numeral) {
  // Key: a root letter with accidentals, optionally followed by a mode word.
  final k = RegExp(r'^([A-G])([#b♯♭]*)\s*(.*)$').firstMatch(key);
  if (k == null) return null;
  var tonicPc = _naturalPitchClasses[k.group(1)!]!;
  final tonicAccidentals = k.group(2)!;
  tonicPc += _accidentalShift(tonicAccidentals);
  final mode = k.group(3)!.toLowerCase();
  // Minor-ish modes read their degrees off the natural-minor scale.
  final minorKey = mode.startsWith('min') ||
      mode == 'm' ||
      mode.startsWith('aeolian') ||
      mode.startsWith('dorian') ||
      mode.startsWith('phrygian') ||
      mode.startsWith('locrian');

  // Numeral: [accidentals][roman][quality marks][figures].
  final n = RegExp(r'^([#b♯♭]*)([ivIV]+)(.*)$').firstMatch(numeral);
  if (n == null) return null;
  final degree = _romanDegrees[n.group(2)!.toLowerCase()];
  if (degree == null) return null;
  final tail = n.group(3)!;

  final offsets = minorKey ? _minorDegreeOffsets : _majorDegreeOffsets;
  final rootPc =
      (tonicPc + offsets[degree - 1] + _accidentalShift(n.group(1)!)) % 12;

  // Quality: explicit marks win, else the numeral's case.
  final upper = n.group(2)![0] == n.group(2)![0].toUpperCase();
  final String harteQuality;
  if (tail.startsWith('ø')) {
    harteQuality = 'hdim7';
  } else if (tail.startsWith('o') || tail.startsWith('°')) {
    harteQuality = 'dim';
  } else if (tail.startsWith('+')) {
    harteQuality = 'aug';
  } else {
    harteQuality = upper ? 'maj' : 'min';
  }

  // Spelling is approximate: we know the pitch class, not the intended letter.
  // A flattened degree (`bIII`) and flat/minor keys spell flat — which is right
  // far more often than not (`bIII` in C is Eb, not D#).
  final numeralAccidentals = n.group(1)!;
  final sharpened =
      numeralAccidentals.contains('#') || numeralAccidentals.contains('♯');
  final flats = numeralAccidentals.contains('b') ||
      numeralAccidentals.contains('♭') ||
      (!sharpened &&
          (tonicAccidentals.contains('b') ||
              tonicAccidentals.contains('♭') ||
              k.group(1) == 'F' ||
              minorKey));
  final rootName = (flats ? _flatSpelling : _sharpSpelling)[(rootPc + 12) % 12];
  return '$rootName${suffixForHarteQuality(harteQuality)}';
}

int _accidentalShift(String accidentals) {
  var shift = 0;
  for (final c in accidentals.split('')) {
    if (c == '#' || c == '♯') shift++;
    if (c == 'b' || c == '♭') shift--;
  }
  return shift;
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
      // Split "TONIC:MODE". ChoCo's weimar partition emits a malformed
      // "Bb-maj" instead of "Bb:major", so accept '-' and ' ' as separators
      // too — otherwise the whole string became the tonic ("Bb-maj major").
      final sep = s.contains(':')
          ? ':'
          : s.contains('-')
              ? '-'
              : ' ';
      final parts = s.split(sep);
      final tonic = parts.first.trim();
      var mode = parts.length > 1 ? parts[1].trim().toLowerCase() : 'major';
      // Those same sources abbreviate the mode.
      mode = const {'maj': 'major', 'min': 'minor'}[mode] ?? mode;
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
