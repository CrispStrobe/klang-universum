// lib/core/curriculum/curriculum.dart
//
// Curriculum alignment: a data model that maps external syllabi onto the games
// the app already has. Both the German wind/percussion proficiency badges
// (Leistungsabzeichen D0–D3) and school Lehrpläne are just different groupings
// over the same atomic skills, so they share one model:
//
//   Curriculum → Level → Topic → [gameIds]
//
// "Readiness" for a level/topic is derived from the child's best stars in the
// mapped games (0..1). Adding a framework or a Bundesland is pure data.
//
// NOTE: the mappings are a practice guide, not an official alignment — the exact
// D1–D3 catalogue varies by Verband, and per-Bundesland Lehrpläne need real
// sourcing. See docs/PLAN.md.

import 'package:klang_universum/l10n/app_localizations.dart';

enum CurriculumFramework { leistungsabzeichen, lehrplan }

/// A syllabus topic and the games that drill it.
class CurriculumTopic {
  const CurriculumTopic(this.title, this.gameIds);
  final String Function(AppLocalizations) title;
  final List<String> gameIds;
}

/// One level within a curriculum (a badge tier, or a Klassenstufe band).
class CurriculumLevel {
  const CurriculumLevel({
    required this.id,
    required this.name,
    required this.badge,
    required this.topics,
  });

  final String id;
  final String Function(AppLocalizations) name;

  /// A short badge/emoji shown on the level card.
  final String badge;
  final List<CurriculumTopic> topics;

  /// All distinct game IDs across this level's topics.
  List<String> get gameIds => {
        for (final t in topics) ...t.gameIds,
      }.toList();
}

/// A named syllabus (a badge system, or a school curriculum for a region).
class Curriculum {
  const Curriculum({
    required this.id,
    required this.framework,
    required this.name,
    required this.levels,
    this.region,
  });

  final String id;
  final CurriculumFramework framework;
  final String Function(AppLocalizations) name;

  /// Bundesland / school-type for a [CurriculumFramework.lehrplan]; null for
  /// the (national) Leistungsabzeichen.
  final String? region;
  final List<CurriculumLevel> levels;
}

// --- Readiness ---------------------------------------------------------------

/// Topic readiness in 0..1: the mean of best-stars/3 over the topic's games.
double topicReadiness(CurriculumTopic topic, int Function(String) starsFor) {
  if (topic.gameIds.isEmpty) return 0;
  final total = topic.gameIds.fold<int>(0, (sum, id) => sum + starsFor(id));
  return total / (topic.gameIds.length * 3);
}

/// Level readiness in 0..1: the mean of its topics' readiness.
double levelReadiness(CurriculumLevel level, int Function(String) starsFor) {
  if (level.topics.isEmpty) return 0;
  final total = level.topics
      .fold<double>(0, (sum, t) => sum + topicReadiness(t, starsFor));
  return total / level.topics.length;
}

// --- Shared topic labels (reused across levels) ------------------------------

CurriculumTopic _reading(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicNoteReading, ids);
CurriculumTopic _values(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicNoteValues, ids);
CurriculumTopic _meter(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicMeter, ids);
CurriculumTopic _dynamics(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicDynamics, ids);
CurriculumTopic _scales(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicScales, ids);
CurriculumTopic _intervals(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicIntervals, ids);
CurriculumTopic _chords(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicChords, ids);
CurriculumTopic _harmony(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicHarmony, ids);
CurriculumTopic _transposition(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicTransposition, ids);
CurriculumTopic _ear(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicEar, ids);
CurriculumTopic _sight(List<String> ids) =>
    CurriculumTopic((l) => l.curTopicSightReading, ids);

// --- The Leistungsabzeichen (D0–D3) ------------------------------------------

final _leistungsabzeichen = Curriculum(
  id: 'leistungsabzeichen',
  framework: CurriculumFramework.leistungsabzeichen,
  name: (l) => l.curLeistungsabzeichen,
  levels: [
    CurriculumLevel(
      id: 'd0',
      name: (l) => l.curLevelD0,
      badge: '🌱',
      topics: [
        _reading(['note_reading_treble', 'note_memory', 'note_order']),
        _values(['note_value_quiz', 'beat_sort', 'beat_count']),
        _ear(['major_minor_ear', 'echo_sequence']),
      ],
    ),
    CurriculumLevel(
      id: 'd1',
      name: (l) => l.curLevelD1,
      badge: '🥉',
      topics: [
        _reading([
          'note_reading_treble',
          'note_reading_bass',
          'line_space',
          'ledger_leap',
        ]),
        _values([
          'note_value_quiz',
          'duration_duel',
          'beat_count',
          'rhythm_tap',
        ]),
        _meter(['time_signature', 'measure_fill', 'beat_runner']),
        _dynamics(['charades']),
        _scales(['scale_detective', 'key_sig']),
        _intervals(['interval_ladder', 'interval_ear']),
        _ear(['major_minor_ear', 'melody_echo']),
      ],
    ),
    CurriculumLevel(
      id: 'd2',
      name: (l) => l.curLevelD2,
      badge: '🥈',
      topics: [
        _scales(['scale_detective', 'scale_builder', 'key_sig']),
        _intervals(['interval_ladder', 'interval_ear']),
        _chords([
          'chord_quiz',
          'triad_builder',
          'name_that_chord',
          'chord_builder',
        ]),
        _meter(['time_signature', 'meter_detective', 'which_beat']),
        _transposition(['concert_pitch']),
        _values(['beat_runner', 'drum_read']),
        _ear(['melody_dictation', 'major_minor_ear']),
      ],
    ),
    CurriculumLevel(
      id: 'd3',
      name: (l) => l.curLevelD3,
      badge: '🥇',
      topics: [
        _chords(['chord_builder', 'name_that_chord', 'chord_grip_hero']),
        _harmony(['harmony_quiz', 'cadence_workshop', 'function_ear']),
        _intervals(['interval_ear', 'interval_ladder']),
        _reading(['note_reading_tenor', 'note_reading_bass', 'duet']),
        _sight(['staff_runner', 'falling_notes', 'grand_staff_read']),
        _ear(['melody_dictation', 'function_ear']),
      ],
    ),
  ],
);

// --- A general school-music guide (Lehrplan-shaped, not a state's official
//     document) — proves the Bundesland-capable model; fill in per state later.

final _schoolGuide = Curriculum(
  id: 'school_general',
  framework: CurriculumFramework.lehrplan,
  name: (l) => l.curSchoolGeneral,
  levels: [
    CurriculumLevel(
      id: 'gs',
      name: (l) => l.curLevelPrimary,
      badge: '🎒',
      topics: [
        _reading(['note_reading_treble', 'note_memory', 'note_order']),
        _values(['note_value_quiz', 'beat_sort', 'rhythm_tap']),
        _meter(['measure_fill', 'beat_runner']),
        _ear(['major_minor_ear', 'echo_sequence']),
      ],
    ),
    CurriculumLevel(
      id: 'sek1',
      name: (l) => l.curLevelLowerSecondary,
      badge: '🏫',
      topics: [
        _reading(['note_reading_treble', 'note_reading_bass', 'ledger_leap']),
        _meter(['time_signature', 'meter_detective']),
        _scales(['scale_detective', 'key_sig']),
        _intervals(['interval_ladder', 'interval_ear']),
        _chords(['chord_quiz', 'name_that_chord']),
        _dynamics(['charades']),
      ],
    ),
    CurriculumLevel(
      id: 'sek2',
      name: (l) => l.curLevelUpperSecondary,
      badge: '🎓',
      topics: [
        _scales(['scale_detective', 'scale_builder']),
        _chords(['chord_builder', 'name_that_chord']),
        _harmony(['harmony_quiz', 'cadence_workshop', 'function_ear']),
        _sight(['staff_runner', 'duet', 'grand_staff_read']),
        _transposition(['concert_pitch']),
      ],
    ),
  ],
);

/// All curricula, badge systems first.
final List<Curriculum> kCurricula = [_leistungsabzeichen, _schoolGuide];
