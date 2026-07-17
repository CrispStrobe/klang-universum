// lib/core/curriculum/interval_songs.dart
//
// Interval MNEMONICS — naming a musical leap by a melody the learner already
// knows. The classic teaching hook: a cuckoo's call ("Kuckuck") is a descending
// minor third; "Alle meine Entchen" opens with a major second; and so on. The
// textbook's interval lessons and the interval games draw on this table.
//
// Songs referenced are public-domain / folk melodies used only by NAME as a
// memory aid (no lyrics or notation reproduced here). Each entry also carries two
// demo MIDI notes that sound the interval exactly, so the audio is always correct
// regardless of any single mnemonic's regional variation — a test asserts the
// demo matches the stated size + direction.

/// One interval, remembered by the tune that starts with it.
class IntervalSong {
  const IntervalSong({
    required this.semitones,
    required this.ascending,
    required this.name,
    required this.song,
    required this.demo,
  });

  /// Interval size in semitones (magnitude, always positive).
  final int semitones;

  /// True if the leap goes up, false if it falls.
  final bool ascending;

  /// Plain interval name in our words ("minor 3rd", "perfect 5th").
  final String name;

  /// The mnemonic melody's name (public domain / folk).
  final String song;

  /// Two MIDI notes that play the interval, in order.
  final List<int> demo;

  /// Signed distance the demo actually spans (for the correctness guard).
  int get demoDelta => demo.last - demo.first;
}

/// The mnemonic table. Ascending unless the song is naturally a falling call.
const List<IntervalSong> kIntervalSongs = [
  IntervalSong(
    semitones: 2,
    ascending: true,
    name: 'major 2nd',
    song: 'Alle meine Entchen',
    demo: [60, 62], // C → D
  ),
  IntervalSong(
    semitones: 3,
    ascending: false,
    name: 'minor 3rd',
    song: 'Kuckuck', // the cuckoo's falling call
    demo: [67, 64], // G → E
  ),
  IntervalSong(
    semitones: 4,
    ascending: true,
    name: 'major 3rd',
    song: 'Kum ba yah',
    demo: [60, 64], // C → E
  ),
  IntervalSong(
    semitones: 5,
    ascending: true,
    name: 'perfect 4th',
    song: 'Tatütata', // the two-tone horn
    demo: [60, 65], // C → F
  ),
  IntervalSong(
    semitones: 7,
    ascending: true,
    name: 'perfect 5th',
    song: 'Morgen kommt der Weihnachtsmann',
    demo: [60, 67], // C → G
  ),
  IntervalSong(
    semitones: 9,
    ascending: true,
    name: 'major 6th',
    song: 'My Bonnie',
    demo: [60, 69], // C → A
  ),
  IntervalSong(
    semitones: 12,
    ascending: true,
    name: 'octave',
    song: 'Over the Rainbow',
    demo: [60, 72], // C → C'
  ),
];

/// The mnemonic for [semitones] in the given direction, or null if we have none.
IntervalSong? intervalSongFor(int semitones, {bool ascending = true}) {
  for (final s in kIntervalSongs) {
    if (s.semitones == semitones && s.ascending == ascending) return s;
  }
  return null;
}
