// lib/features/games/note_reading/step_skip_screen.dart
//
// "Step or Skip?" — a reading drill on melodic *motion*: two notes sit on the
// staff, and the child decides whether the second one is a STEP away (the very
// next line-or-space, a 2nd) or a SKIP (a bigger jump — a 3rd, 4th or 5th).
// Steps-vs-skips is one of the first things young readers learn to see; naming
// the exact interval comes later (Connect the Steps). No staff-height reference
// is needed — it is purely "are they neighbours or not?". Big staff card, two
// tap buttons, no-fail loop.
//
// SRI: 'reading.motion.<step|skip>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

const _half = NoteDuration(DurationBase.half);

class StepSkipScreen extends StatefulWidget {
  const StepSkipScreen({super.key});

  @override
  State<StepSkipScreen> createState() => _StepSkipScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class StepSkipTester {
  /// Whether the two notes are a step apart (the correct answer).
  bool get answerStep;
  bool get isFinished;
}

class _StepSkipScreenState extends State<StepSkipScreen>
    with QuizRoundMixin
    implements StepSkipTester {
  @override
  bool get answerStep => _step;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late Pitch _a; // first note
  late Pitch _b; // second note
  late bool _step; // are they a 2nd apart?
  bool? _tapped; // last choice (true = step)
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'step_skip';

  // A correct answer sounds the two notes; a miss buzzes. No generic blips.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // A step is a 2nd (one staff position); a skip is a 3rd/4th/5th (2..4).
    _step = _random.nextBool();
    final delta = _step ? 1 : 2 + _random.nextInt(3); // 1, or 2..4
    // Keep both notes comfortably on/around the treble staff [-1 .. 9].
    final low = -1 + _random.nextInt(9 - delta + 1); // low..low+delta ≤ 9
    final up = _random.nextBool();
    final aPos = up ? low : low + delta;
    final bPos = up ? low + delta : low;
    _a = Clef.treble.pitchAt(aPos);
    _b = Clef.treble.pitchAt(bPos);
    _tapped = null;
    _lastAnswer = null;
  }

  void _onAnswer(bool step) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = step == _step;
    final audio = context.read<AudioService>();

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'reading.motion.${_step ? 'step' : 'skip'}',
            correct,
          );
    }
    if (correct) {
      audio.playPhrase([_a.midiNumber, _b.midiNumber], noteMs: 380);
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = step;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(_a, _half, id: 'a'),
            NoteElement.note(_b, _half, id: 'b'),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameStepSkip),
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
                      prompt: l10n.stepSkipPrompt,
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
                            child: StaffView(
                              score: _cardScore,
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
                    Row(
                      children: [
                        for (final step in const [true, false])
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
                                      : step == _step && _tapped == _step
                                          ? Colors.green
                                          : step == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  step ? Icons.stairs : Icons.trending_up,
                                ),
                                onPressed: () => _onAnswer(step),
                                label: Text(
                                  step ? l10n.stepLabel : l10n.skipLabel,
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
