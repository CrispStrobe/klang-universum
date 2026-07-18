// lib/features/games/note_reading/enharmonic_screen.dart
//
// "Enharmonic Twins" — reading enharmonic equivalence, a Sek-I theory staple no
// other game drills. Two notes are shown on the staff, each with its own
// accidental; the child decides whether they are the SAME sound spelled two ways
// (F♯ = G♭) or two GENUINELY different pitches. The answer is graded by comparing
// the sounding pitch (`midiNumber`), so it is exact — the child must hear/compute
// past the spelling, not just compare letters. Big staff card, two tap buttons.
//
// Star-gated: the five sharp/flat twins for beginners; the trickier white-key
// twins (E♯=F, F♭=E) join at 2★. SRI: 'reading.enharmonic.<yes|no>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _whole = NoteDuration(DurationBase.whole);

/// A (step, alter) spelling — the octave is filled in per round.
typedef _Spelling = (Step, int);

/// Same-octave enharmonic twins: two spellings of one pitch class.
const _sharpFlatTwins = <(_Spelling, _Spelling)>[
  ((Step.c, 1), (Step.d, -1)), // C♯ / D♭
  ((Step.d, 1), (Step.e, -1)), // D♯ / E♭
  ((Step.f, 1), (Step.g, -1)), // F♯ / G♭
  ((Step.g, 1), (Step.a, -1)), // G♯ / A♭
  ((Step.a, 1), (Step.b, -1)), // A♯ / B♭
];

/// The white-key twins — subtler because one note carries no accidental. Only at 2★.
const _whiteKeyTwins = <(_Spelling, _Spelling)>[
  ((Step.e, 1), (Step.f, 0)), // E♯ / F
  ((Step.f, -1), (Step.e, 0)), // F♭ / E
];

class EnharmonicScreen extends StatefulWidget {
  const EnharmonicScreen({super.key});

  @override
  State<EnharmonicScreen> createState() => _EnharmonicScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class EnharmonicTester {
  /// Whether the two notes sound the same pitch — the correct answer.
  bool get answerSame;
  bool get isFinished;

  /// Invariant guard: [answerSame] must equal same-sounding-pitch.
  bool get notesShareMidi;
}

class _EnharmonicScreenState extends State<EnharmonicScreen>
    with QuizRoundMixin
    implements EnharmonicTester {
  final _random = Random();
  final _pb = ScorePlayback();

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  late Pitch _a;
  late Pitch _b;
  late bool _same; // do the two notes sound the same pitch?
  bool? _tapped; // last choice (true = same)
  bool? _lastAnswer;
  bool _wide = false;

  @override
  bool get answerSame => _same;
  @override
  bool get isFinished => finished;
  @override
  bool get notesShareMidi => _a.midiNumber == _b.midiNumber;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'enharmonic';

  // A correct answer sounds the two notes; a miss buzzes.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    _wide = context.read<ProgressService>().starsFor(gameType) >= 2;
    prepareRound();
  }

  @override
  void prepareRound() {
    _same = _random.nextBool();
    // A comfortable treble octave for both spellings.
    final octave = 4 + _random.nextInt(2); // 4..5
    if (_same) {
      final pool = [
        ..._sharpFlatTwins,
        if (_wide) ..._whiteKeyTwins,
      ];
      final (s1, s2) = pool[_random.nextInt(pool.length)];
      // Randomly order which spelling appears first.
      final first = _random.nextBool();
      _a = _pitch(first ? s1 : s2, octave);
      _b = _pitch(first ? s2 : s1, octave);
    } else {
      // Two genuinely different pitches that still look close (adjacent steps,
      // at least one accidental), so it is a real reading test — never an
      // accidental enharmonic match.
      _a = _pitch((_step(_random.nextInt(7)), _randomAlter()), octave);
      do {
        final stepShift = _random.nextBool() ? 1 : -1;
        final bStep = _step((_a.step.index + stepShift) % 7);
        _b = _pitch((bStep, _randomAlter()), octave);
      } while (
          _b.midiNumber == _a.midiNumber || (_a.alter == 0 && _b.alter == 0));
    }
    _tapped = null;
    _lastAnswer = null;
  }

  Pitch _pitch(_Spelling s, int octave) =>
      Pitch(s.$1, alter: s.$2, octave: octave);

  Step _step(int i) => Step.values[i % 7];

  int _randomAlter() => const [-1, 0, 1][_random.nextInt(3)];

  void _onAnswer(bool same) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = same == _same;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.enharmonic.${_same ? 'yes' : 'no'}',
            correct,
          );
    }
    if (correct) {
      audio.playPhrase([_a.midiNumber, _b.midiNumber], noteMs: 420);
      _pb.play([
        (ids: {'a'}, ms: 420),
        (ids: {'b'}, ms: 420),
      ]);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = same;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(_a, _whole, id: 'a', showAccidental: true),
          ]),
          Measure([
            NoteElement.note(_b, _whole, id: 'b', showAccidental: true),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameEnharmonic),
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
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.enharmonicPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: PlayingStaffView(
                              score: _cardScore,
                              controller: _pb,
                              staffSpace: 14,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerRow(
                      children: [
                        for (final same in const [true, false])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : same == _same && _tapped == _same
                                          ? Colors.green
                                          : same == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  same ? Icons.equalizer : Icons.compare_arrows,
                                ),
                                onPressed: () => _onAnswer(same),
                                label: Text(
                                  same
                                      ? l10n.enharmonicSame
                                      : l10n.enharmonicDifferent,
                                ),
                              ),
                            ),
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
