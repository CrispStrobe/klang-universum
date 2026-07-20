// lib/features/games/songs/import/jams.dart
//
// JAMS (JSON Annotated Music Specification) importer — the MIR-standard
// annotation format that ships the big chord/beat/key datasets (Isophonics,
// Billboard, RWC, …). This slice imports the **chord** annotation: it maps each
// Harte-syntax chord label to a plain chord name and emits a ChordPro string, so
// the whole existing chord-sheet pipeline (parseChordPro → ImportedChordSheet →
// playback) is reused unchanged.
//
// Harte labels look like `C:maj`, `A:min7`, `G:7/3`, `F#:hdim7`, `N` (no chord).
// The app reduces every chord to a plain major/minor triad, so we only need the
// root and whether it is minor — extensions and bass inversions are dropped.
//
// Pure Dart (no Flutter): unit-testable, and the same converter can back a CLI.

import 'dart:convert';

/// Converts a JAMS document [json] into ChordPro source text.
///
/// Picks the first chord annotation (namespace `chord` or `chord_harte`),
/// converts each observation's Harte label to a plain chord name, collapses
/// consecutive repeats, and lays the chords out a few per line. The JAMS
/// `file_metadata.title` becomes the `{title: …}` directive.
///
/// Throws [FormatException] when the JSON is not a JAMS object or carries no
/// usable chord annotation.
String jamsToChordPro(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } catch (_) {
    throw const FormatException('Not valid JSON — expected a JAMS file.');
  }
  if (root is! Map<String, dynamic>) {
    throw const FormatException('Not a JAMS object.');
  }

  final chords = <String>[];
  String? last;
  for (final label in _chordLabels(root)) {
    final name = harteToChordName(label);
    if (name == null) {
      last = null; // a rest (N/X) breaks a run so the next chord still shows
      continue;
    }
    if (name == last) continue; // collapse consecutive repeats
    chords.add(name);
    last = name;
  }
  if (chords.isEmpty) {
    throw const FormatException(
      'No chord annotation found in the JAMS file.',
    );
  }

  final title = _title(root);
  final buffer = StringBuffer('{title: $title}\n\n');
  // ~4 chords per line reads like a lead sheet; the middot gives each chip a
  // visible anchor over otherwise-empty lyric text.
  for (var i = 0; i < chords.length; i += 4) {
    final row = chords.skip(i).take(4).map((c) => '[$c]·').join('  ');
    buffer.writeln(row);
  }
  return buffer.toString();
}

/// The chord labels from the first chord annotation in [root], in time order.
/// Handles both JAMS data shapes: a list of observation objects, and the older
/// dict-of-parallel-arrays. Returns an empty iterable if there is no chord
/// annotation.
Iterable<String> _chordLabels(Map<String, dynamic> root) {
  final annotations = root['annotations'];
  if (annotations is! List) return const [];
  for (final a in annotations) {
    if (a is! Map) continue;
    final ns = a['namespace'];
    if (ns != 'chord' && ns != 'chord_harte') continue;
    final data = a['data'];
    if (data is List) {
      // Modern JAMS: [{time, duration, value, confidence}, …].
      return [
        for (final obs in data)
          if (obs is Map && obs['value'] is String) obs['value'] as String,
      ];
    }
    if (data is Map && data['value'] is List) {
      // Legacy sparse JAMS: {time: [...], value: [...], …}.
      return [
        for (final v in data['value'] as List)
          if (v is String) v,
      ];
    }
  }
  return const [];
}

String _title(Map<String, dynamic> root) {
  final meta = root['file_metadata'];
  if (meta is Map && meta['title'] is String) {
    final t = (meta['title'] as String).trim();
    if (t.isNotEmpty) return t;
  }
  return 'JAMS chords';
}

/// Maps a Harte chord [label] to a plain chord name (`C`, `Am`, `F#`, `Bbm`),
/// or null for a no-chord / unparseable label.
///
/// The app reduces chords to a major/minor triad, so only the root and the
/// major-vs-minor quality survive; extensions (`7`, `maj7`, `sus4`, …) and a
/// slash bass (`/3`, `/b7`) are dropped. Diminished/half-diminished qualities
/// map to a minor triad (the nearest triad the app renders).
String? harteToChordName(String label) {
  final s = label.trim();
  if (s.isEmpty || s == 'N' || s == 'X') return null;

  // Root: a letter A–G plus any accidentals (#/b). The app plays a single
  // accidental; a rare double still renders as a chip (just won't sound).
  final m = RegExp(r'^([A-G])([#b]*)').firstMatch(s);
  if (m == null) return null;
  final root = '${m.group(1)}${m.group(2)}';

  // Quality: everything after ':' up to a '/' bass marker. No ':' ⇒ major.
  final colon = s.indexOf(':');
  var quality = '';
  if (colon >= 0) {
    quality = s.substring(colon + 1);
    final slash = quality.indexOf('/');
    if (slash >= 0) quality = quality.substring(0, slash);
    quality = quality.trim();
  }
  final isMinor = quality.startsWith('min') ||
      quality.startsWith('dim') ||
      quality.startsWith('hdim');
  return isMinor ? '${root}m' : root;
}
