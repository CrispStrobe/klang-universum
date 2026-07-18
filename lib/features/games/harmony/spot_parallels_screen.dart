// lib/features/games/harmony/spot_parallels_screen.dart
//
// "Spot the Parallels" — the classic part-writing skill: two four-voice (SATB)
// chords are engraved on a grand staff; the child decides whether the motion
// between them is CLEAN or slips into forbidden **parallel fifths / octaves**.
// The answer key is crisp_notation_core's `checkVoiceLeading` — the library is
// ground truth, so a template can never be mislabelled. Templates are verified
// clean/parallel-only once (see the test), then transposed for variety: parallels
// depend only on intervals, so transposition preserves the label.
//
// Top of the harmony ladder (expert tier). SRI: 'harmony.parallels.<template>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// One authored SATB chord-pair pattern. MIDI notes are top→bottom (S, A, T, B),
/// in C; [hasParallels] is what `checkVoiceLeading` reports (asserted in tests).
class ParallelsTemplate {
  const ParallelsTemplate(this.id, this.chord1, this.chord2, this.hasParallels);

  /// Short slug for the SRI item id.
  final String id;
  final List<int> chord1; // [S, A, T, B]
  final List<int> chord2;
  final bool hasParallels;
}

/// The verified pattern pool — 4 clean, 5 with parallel fifths/octaves. Every
/// entry's [ParallelsTemplate.hasParallels] is checked against the library in
/// `spot_parallels_test.dart`, and the parallel ones are parallel-*only* (no
/// crossing/spacing/hidden) so the question stays crisp.
const kParallelsTemplates = <ParallelsTemplate>[
  // Clean.
  ParallelsTemplate('iv', [67, 64, 60, 48], [69, 65, 60, 53], false),
  ParallelsTemplate('vi', [71, 62, 55, 43], [72, 60, 55, 48], false),
  ParallelsTemplate('vii', [64, 60, 57, 45], [65, 62, 57, 50], false),
  ParallelsTemplate('v45', [69, 65, 60, 53], [71, 62, 55, 43], false),
  // Parallel fifths / octaves.
  ParallelsTemplate('p1', [64, 60, 55, 48], [62, 59, 55, 47], true),
  ParallelsTemplate('p2', [67, 64, 60, 48], [69, 65, 62, 50], true),
  ParallelsTemplate('p3', [72, 64, 55, 48], [74, 65, 57, 50], true),
  ParallelsTemplate('p4', [60, 55, 52, 48], [62, 57, 54, 50], true),
  ParallelsTemplate('p5', [67, 60, 55, 48], [69, 62, 57, 50], true),
];

/// Transposition offsets (semitones) that keep every template inside a
/// comfortable grand-staff range. Interval-preserving, so the clean/parallel
/// label is unchanged.
const _offsets = [0, 2, 5, 7, -3, -5];

/// A ready-to-render round: the two chords (as Pitches, top→bottom) and whether
/// the motion contains parallels.
class ParallelsRound {
  const ParallelsRound(
    this.chord1,
    this.chord2,
    this.hasParallels,
    this.itemId,
  );
  final List<Pitch> chord1;
  final List<Pitch> chord2;
  final bool hasParallels;
  final String itemId;
}

/// Builds a round from [template] transposed by [offset] semitones.
ParallelsRound buildRound(ParallelsTemplate template, int offset) =>
    ParallelsRound(
      [for (final m in template.chord1) Pitch.fromMidi(m + offset)],
      [for (final m in template.chord2) Pitch.fromMidi(m + offset)],
      template.hasParallels,
      'harmony.parallels.${template.id}',
    );

class SpotParallelsScreen extends StatefulWidget {
  const SpotParallelsScreen({super.key});

  @override
  State<SpotParallelsScreen> createState() => _SpotParallelsScreenState();
}

class _SpotParallelsScreenState extends State<SpotParallelsScreen>
    with QuizRoundMixin {
  final _random = Random();

  late ParallelsRound _round;
  bool? _tapped; // the child's last answer (null = unanswered)

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'spot_parallels';

  // The screen plays the chord pair itself; skip the generic blips.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Alternate the intended answer so a session is ~half clean, half parallel.
    final wantParallel = round.isOdd;
    final pool = kParallelsTemplates
        .where((t) => t.hasParallels == wantParallel)
        .toList();
    final template = pool[_random.nextInt(pool.length)];
    final offset = _offsets[_random.nextInt(_offsets.length)];
    _round = buildRound(template, offset);
    _tapped = null;
  }

  static const _whole = NoteDuration(DurationBase.whole);

  NoteElement _chord(List<Pitch> voices) =>
      NoteElement(pitches: voices, duration: _whole);

  /// SATB on a grand staff: soprano + alto on the treble, tenor + bass on the
  /// bass staff, two measures (the pair of chords).
  GrandStaff get _grandStaff => GrandStaff(
        upper: Score(
          clef: Clef.treble,
          measures: [
            Measure([_chord(_round.chord1.sublist(0, 2))]),
            Measure([_chord(_round.chord2.sublist(0, 2))]),
          ],
        ),
        lower: Score(
          clef: Clef.bass,
          measures: [
            Measure([_chord(_round.chord1.sublist(2))]),
            Measure([_chord(_round.chord2.sublist(2))]),
          ],
        ),
      );

  void _listen() {
    context.read<AudioService>().playChordSequence([
      [for (final p in _round.chord1) p.midiNumber],
      [for (final p in _round.chord2) p.midiNumber],
    ]);
  }

  void _onAnswer(bool saysParallel) {
    if (_tapped != null && _lastCorrect) return; // round already resolved
    final correct = saysParallel == _round.hasParallels;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_round.itemId, correct);
    }

    if (correct) {
      _listen(); // hear the (correctly-judged) motion
    } else {
      audio.playWrong();
    }

    setState(() => _tapped = saysParallel);
    resolveAnswer(correct: correct);
  }

  bool get _lastCorrect => _tapped != null && _tapped == _round.hasParallels;

  Color? _buttonColor(bool option) {
    if (_tapped == null) return null;
    final isAnswer = option == _round.hasParallels;
    if (isAnswer && _tapped == _round.hasParallels) return Colors.green;
    if (option == _tapped && !isAnswer) return Colors.redAccent;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final correct = _tapped == null ? null : _lastCorrect;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameSpotParallels),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: correct,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.spotParallelsPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: GrandStaffView(
                              grandStaff: _grandStaff,
                              staffSpace: 13,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _listen,
                      icon: const Icon(Icons.volume_up),
                      label: Text(l10n.spotParallelsListen),
                    ),
                    FeedbackLine(correct: correct),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _buttonColor(false),
                          ),
                          onPressed: () => _onAnswer(false),
                          child: Text(l10n.spotParallelsClean),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _buttonColor(true),
                          ),
                          onPressed: () => _onAnswer(true),
                          child: Text(l10n.spotParallelsParallel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
