// lib/features/games/songs/song_book.dart
//
// The song book: public-domain children's songs as partitura DSL melodies
// with lyrics. Titles stay in their original language (that's the song's
// name); everything around them is localized.

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:partitura/partitura.dart'
    show NoteElement, Score, TimeSignature;

/// Playable sequence for any single-voice [score]:
/// (elementId, midi, milliseconds) in reading order.
List<(String, int, int)> playbackOf(Score score, {int quarterMs = 500}) {
  final result = <(String, int, int)>[];
  for (final measure in score.measures) {
    for (final element in measure.elements) {
      if (element is NoteElement && element.id != null) {
        final (num, den) = element.duration.fraction;
        final ms = (4 * quarterMs * num / den).round();
        result.add((element.id!, element.pitches.first.midiNumber, ms));
      }
    }
  }
  return result;
}

class Song {
  final String id;
  final String title;
  final String dsl;
  final String lyrics;
  final TimeSignature timeSignature;

  /// Milliseconds per quarter note when playing.
  final int quarterMs;

  const Song({
    required this.id,
    required this.title,
    required this.dsl,
    required this.lyrics,
    this.timeSignature = TimeSignature.fourFour,
    this.quarterMs = 500,
  });

  Score get score => Score.simple(
        timeSignature: timeSignature,
        notes: dsl,
        lyrics: lyrics,
      );

  /// Playable sequence: (elementId, midi, milliseconds) in reading order.
  List<(String, int, int)> get playback =>
      playbackOf(score, quarterMs: quarterMs);
}

const kSongs = <Song>[
  Song(
    id: 'alle_meine_entchen',
    title: 'Alle meine Entchen',
    dsl: 'c4:q d4 e4 f4 | g4:h g4 | a4:q a4 a4 a4 | g4:w | '
        'a4:q a4 a4 a4 | g4:w | f4:q f4 f4 f4 | e4:h e4 | '
        'g4:q g4 g4 g4 | c4:w',
    lyrics: 'Al- le mei- ne Ent- chen schwim- men auf dem See, '
        'schwim- men auf dem See, Köpf- chen in das Was- ser, '
        'Schwänz- chen in die Höh.',
  ),
  Song(
    id: 'haenschen_klein',
    title: 'Hänschen klein',
    dsl: 'g4:q e4 e4:h | f4:q d4 d4:h | c4:q d4 e4 f4 | g4 g4 g4:h',
    lyrics: 'Häns- chen klein ging al- lein in die wei- te Welt hin- ein.',
  ),
  Song(
    id: 'twinkle',
    title: 'Twinkle, Twinkle, Little Star',
    dsl: 'c4:q c4 g4 g4 | a4 a4 g4:h | f4:q f4 e4 e4 | d4 d4 c4:h',
    lyrics: 'Twin- kle, twin- kle, lit- tle star, '
        'how I won- der what you are.',
  ),
  Song(
    id: 'mary_lamb',
    title: 'Mary Had a Little Lamb',
    dsl: 'e4:q d4 c4 d4 | e4 e4 e4:h | d4:q d4 d4:h | e4:q g4 g4:h | '
        'e4:q d4 c4 d4 | e4 e4 e4 e4 | d4:q d4 e4 d4 | c4:w',
    lyrics: 'Ma- ry had a lit- tle lamb, lit- tle lamb, lit- tle lamb, '
        'Ma- ry had a lit- tle lamb whose fleece was white as snow.',
  ),
  Song(
    id: 'old_macdonald',
    title: 'Old MacDonald Had a Farm',
    dsl: 'g4:q g4 g4 d4 | e4 e4 d4:h | b4:q b4 a4 a4 | g4:w',
    lyrics: 'Old Mac- Don- ald had a farm, E- I- E- I- O.',
  ),
];
