// lib/features/games/songs/import/chord_quality.dart
//
// The shared chord-quality vocabulary — the single source of truth linking three
// representations of a chord's quality:
//   • the Harte label quality  ("min7", "maj7", "hdim7", …) used by JAMS / MIR,
//   • the display symbol suffix ("m7",  "maj7", "m7b5",  …) shown on a chip,
//   • the semitone intervals from the root, used to VOICE the chord.
//
// Both the JAMS importer (Harte ↔ symbol) and playback (symbol → intervals) read
// this table, so a `A:min7` label survives import as "Am7", plays as an actual
// minor-seventh, and exports back to `A:min7` — a lossless round-trip for the
// common vocabulary. Qualities outside the table fall back to the nearest
// triad/quality so nothing ever fails to parse.
//
// Pure Dart (no crisp_notation): usable from the Flutter-free CLI.

/// One chord quality: its display [suffix], the Harte quality names that map to
/// it ([harte], first is canonical for export), and the [intervals] (semitones
/// from the root) that voice it.
class ChordQualitySpec {
  const ChordQualitySpec(this.suffix, this.harte, this.intervals);
  final String suffix;
  final List<String> harte;
  final List<int> intervals;
}

/// The vocabulary, most-common first.
const chordQualities = <ChordQualitySpec>[
  ChordQualitySpec('', ['maj'], [0, 4, 7]),
  ChordQualitySpec('m', ['min'], [0, 3, 7]),
  ChordQualitySpec('dim', ['dim'], [0, 3, 6]),
  ChordQualitySpec('aug', ['aug'], [0, 4, 8]),
  ChordQualitySpec('sus2', ['sus2'], [0, 2, 7]),
  ChordQualitySpec('sus4', ['sus4'], [0, 5, 7]),
  ChordQualitySpec('6', ['maj6', '6'], [0, 4, 7, 9]),
  ChordQualitySpec('m6', ['min6'], [0, 3, 7, 9]),
  ChordQualitySpec('7', ['7'], [0, 4, 7, 10]),
  ChordQualitySpec('maj7', ['maj7'], [0, 4, 7, 11]),
  ChordQualitySpec('m7', ['min7'], [0, 3, 7, 10]),
  ChordQualitySpec('m7b5', ['hdim7'], [0, 3, 6, 10]),
  ChordQualitySpec('dim7', ['dim7'], [0, 3, 6, 9]),
  ChordQualitySpec('mMaj7', ['minmaj7'], [0, 3, 7, 11]),
  ChordQualitySpec('9', ['9'], [0, 4, 7, 10, 14]),
  ChordQualitySpec('maj9', ['maj9'], [0, 4, 7, 11, 14]),
  ChordQualitySpec('m9', ['min9'], [0, 3, 7, 10, 14]),
  ChordQualitySpec('add9', ['add9'], [0, 4, 7, 14]),
];

final Map<String, List<int>> _bySuffix = {
  for (final q in chordQualities) q.suffix: q.intervals,
};
final Map<String, String> _harteToSuffix = {
  for (final q in chordQualities)
    for (final h in q.harte) h: q.suffix,
};
final Map<String, String> _suffixToHarte = {
  for (final q in chordQualities) q.suffix: q.harte.first,
};

/// Semitone intervals for a display [suffix] (e.g. `m7` → [0,3,7,10]); an
/// unknown suffix falls back to a minor triad if it starts with `m` (but not
/// `maj`), else a major triad — so any user-typed chord still voices sensibly.
List<int> intervalsForSuffix(String suffix) =>
    _bySuffix[suffix] ??
    (suffix.startsWith('m') && !suffix.startsWith('maj')
        ? const [0, 3, 7]
        : const [0, 4, 7]);

/// The display suffix for a Harte quality (e.g. `min7` → `m7`, `maj` → ``).
/// Unknown qualities reduce to the nearest base quality.
String suffixForHarteQuality(String harteQuality) {
  final q = harteQuality.trim();
  final exact = _harteToSuffix[q];
  if (exact != null) return exact;
  if (q.startsWith('minmaj')) return 'mMaj7';
  if (q.startsWith('hdim')) return 'm7b5';
  if (q.startsWith('dim')) return 'dim';
  if (q.startsWith('aug')) return 'aug';
  if (q.startsWith('sus2')) return 'sus2';
  if (q.startsWith('sus')) return 'sus4';
  // maj9/maj11/maj13 (not in the table) → major base — NOT minor, so this must
  // precede the 'm' check below.
  if (q.startsWith('maj')) return '';
  if (q.startsWith('min') || q.startsWith('m')) return 'm';
  return ''; // dominant extensions (9, 11, 13, …) → major base
}

/// The canonical Harte quality for a display [suffix] (the inverse of
/// [suffixForHarteQuality] for the vocabulary).
String harteQualityForSuffix(String suffix) => _suffixToHarte[suffix] ?? 'maj';

/// Splits a chord symbol into its root (letter + accidentals) and quality
/// suffix (`C#m7` → root `C#`, suffix `m7`). Null if there is no root letter.
({String root, String suffix})? splitChordSymbol(String name) {
  final m = RegExp(r'^([A-Ga-g][#b]*)(.*)$').firstMatch(name.trim());
  if (m == null) return null;
  final r = m.group(1)!;
  return (root: r[0].toUpperCase() + r.substring(1), suffix: m.group(2)!);
}
