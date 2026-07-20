// lib/features/games/songs/song_book.dart
//
// The song book: public-domain children's songs as crisp_notation DSL melodies
// with lyrics. Titles stay in their original language (that's the song's
// name); everything around them is localized.

// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:crisp_notation/crisp_notation.dart'
    show MultiPartScore, NoteElement, RestElement, Score, TimeSignature;

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
  Song(
    id: 'bruder_jakob',
    title: 'Bruder Jakob',
    dsl: 'c4:q d4 e4 c4 | c4 d4 e4 c4 | e4 f4 g4:h | e4:q f4 g4:h | '
        'g4:e a4 g4 f4 e4:q c4 | g4:e a4 g4 f4 e4:q c4 | '
        'c4:q g3 c4:h | c4:q g3 c4:h',
    lyrics: 'Bru- der Ja- kob, Bru- der Ja- kob, schläfst du noch, '
        'schläfst du noch, hörst du nicht die Glo- cken, '
        'hörst du nicht die Glo- cken, ding dang dong, ding dang dong.',
  ),
  Song(
    id: 'ode_to_joy',
    title: 'Ode an die Freude',
    dsl: 'e4:q e4 f4 g4 | g4 f4 e4 d4 | c4 c4 d4 e4 | e4 d4 d4:h',
    lyrics: 'Freu- de, schö- ner Göt- ter- fun- ken, '
        'Toch- ter aus E- ly- si- um.',
  ),
  Song(
    id: 'jingle_bells',
    title: 'Jingle Bells',
    dsl: 'e4:q e4 e4:h | e4:q e4 e4:h | e4:q g4 c4 d4 | e4:w',
    lyrics: 'Jin- gle bells, jin- gle bells, jin- gle all the way,',
  ),
  Song(
    id: 'london_bridge',
    title: 'London Bridge Is Falling Down',
    dsl: 'g4:q a4 g4 f4 | e4:q f4 g4:h | d4:q e4 f4:h | e4:q f4 g4:h | '
        'g4:q a4 g4 f4 | e4:q f4 g4:h | d4:q g4 e4 c4',
    lyrics: 'Lon- don Bridge is fall- ing down, fall- ing down, '
        'fall- ing down, Lon- don Bridge is fall- ing down, '
        'my fair la- dy.',
  ),
  Song(
    id: 'hot_cross_buns',
    title: 'Hot Cross Buns',
    dsl: 'e4:q d4 c4:h | e4:q d4 c4:h | c4:e c4 c4 c4 d4 d4 d4 d4 | '
        'e4:q d4 c4:h',
    lyrics: 'Hot cross buns, hot cross buns, one a pen- ny, '
        'two a pen- ny, hot cross buns.',
  ),
];

// ─── Ensemble songs (2–5 voices) ─────────────────────────────────────────────

/// One voice of an [EnsembleSong]: a monophonic melodic line as DSL, with an
/// optional lyric line (only voice 1 of a round usually carries the words).
class EnsembleVoice {
  final String name;
  final String dsl;
  final String? lyrics;

  const EnsembleVoice({required this.name, required this.dsl, this.lyrics});

  Score get score => lyrics == null
      ? Score.simple(notes: dsl)
      : Score.simple(notes: dsl, lyrics: lyrics!);
}

/// A public-domain song for several voices — a round/canon or a harmonised
/// part-song. Each [EnsembleVoice] is one staff; together they form a
/// [MultiPartScore] (exportable, and rendered as stacked staves).
class EnsembleSong {
  final String id;
  final String title;
  final List<EnsembleVoice> voices;

  /// Milliseconds per quarter note when playing.
  final int quarterMs;

  const EnsembleSong({
    required this.id,
    required this.title,
    required this.voices,
    this.quarterMs = 500,
  });

  MultiPartScore get score => MultiPartScore([for (final v in voices) v.score]);

  List<String> get partNames => [for (final v in voices) v.name];
}

/// Playback for one ensemble voice — like [playbackOf] but REST-AWARE: rests
/// become silent `([], ms)` gaps so a canon's staggered entries line up. Feed
/// the per-voice lists straight to `AudioService.playMixedTimedChords`.
List<(List<int>, int)> ensembleVoicePlayback(
  Score score, {
  int quarterMs = 500,
}) {
  final out = <(List<int>, int)>[];
  for (final measure in score.measures) {
    for (final e in measure.elements) {
      if (e is NoteElement) {
        final (n, d) = e.duration.fraction;
        final ms = (4 * quarterMs * n / d).round();
        out.add(([e.pitches.first.midiNumber], ms));
      } else if (e is RestElement) {
        final (n, d) = e.duration.fraction;
        final ms = (4 * quarterMs * n / d).round();
        out.add((const <int>[], ms));
      }
    }
  }
  return out;
}

// The 8-bar Bruder Jakob melody, reused staggered for the round.
const _bruderMelody = 'c4:q d4 e4 c4 | c4 d4 e4 c4 | e4 f4 g4:h | '
    'e4:q f4 g4:h | g4:e a4 g4 f4 e4:q c4 | g4:e a4 g4 f4 e4:q c4 | '
    'c4:q g3 c4:h | c4:q g3 c4:h';
const _bruderLyrics = 'Bru- der Ja- kob, Bru- der Ja- kob, schläfst du noch, '
    'schläfst du noch, hörst du nicht die Glo- cken, '
    'hörst du nicht die Glo- cken, ding dang dong, ding dang dong.';

/// A [voices]-part round of [melody]: each voice enters [staggerBars] bars after
/// the previous one (leading/trailing whole-rest bars keep every voice the same
/// length), so it plays back as a true canon. Voice 1 carries [lyrics].
EnsembleSong _round({
  required String id,
  required String title,
  required String melody,
  required String lyrics,
  required int voices,
  int staggerBars = 2,
}) {
  String restBars(int n) => List.filled(n, 'r:w').join(' | ');
  final totalRest = (voices - 1) * staggerBars;
  final vs = <EnsembleVoice>[
    for (var i = 0; i < voices; i++)
      EnsembleVoice(
        name: '${i + 1}',
        dsl: [
          if (i * staggerBars > 0) restBars(i * staggerBars),
          melody,
          if (totalRest - i * staggerBars > 0)
            restBars(totalRest - i * staggerBars),
        ].join(' | '),
        lyrics: i == 0 ? lyrics : null,
      ),
  ];
  return EnsembleSong(id: id, title: title, voices: vs);
}

final kEnsembleSongs = <EnsembleSong>[
  _round(
    id: 'bruder_jakob_canon2',
    title: 'Bruder Jakob (Kanon, 2 Stimmen)',
    melody: _bruderMelody,
    lyrics: _bruderLyrics,
    voices: 2,
  ),
  _round(
    id: 'bruder_jakob_canon4',
    title: 'Bruder Jakob (Kanon, 4 Stimmen)',
    melody: _bruderMelody,
    lyrics: _bruderLyrics,
    voices: 4,
  ),
  const EnsembleSong(
    id: 'ode_to_joy_duet',
    title: 'Ode an die Freude (2 Stimmen)',
    voices: [
      EnsembleVoice(
        name: 'Melodie',
        dsl: 'e4:q e4 f4 g4 | g4 f4 e4 d4 | c4 c4 d4 e4 | e4 d4 d4:h',
        lyrics: 'Freu- de, schö- ner Göt- ter- fun- ken, '
            'Toch- ter aus E- ly- si- um.',
      ),
      EnsembleVoice(
        name: 'Bass',
        dsl: 'c3:w | g3:w | c3:w | g3:h c3:h',
      ),
    ],
  ),
  const EnsembleSong(
    id: 'alle_meine_entchen_duet',
    title: 'Alle meine Entchen (2 Stimmen)',
    voices: [
      EnsembleVoice(
        name: 'Melodie',
        dsl: 'c4:q d4 e4 f4 | g4:h g4 | a4:q a4 a4 a4 | g4:w | '
            'a4:q a4 a4 a4 | g4:w | f4:q f4 f4 f4 | e4:h e4 | '
            'g4:q g4 g4 g4 | c4:w',
        lyrics: 'Al- le mei- ne Ent- chen schwim- men auf dem See, '
            'schwim- men auf dem See, Köpf- chen in das Was- ser, '
            'Schwänz- chen in die Höh.',
      ),
      EnsembleVoice(
        name: 'Bass',
        dsl: 'c3:w | g3:w | c3:w | g3:w | c3:w | g3:w | f3:w | c3:w | '
            'g3:w | c3:w',
      ),
    ],
  ),
];
