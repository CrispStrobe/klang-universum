// lib/features/games/composition/question_answer_screen.dart
//
// "Frage & Antwort" — antecedent/consequent phrases, the seed of classical
// phrase-building: a QUESTION phrase plays (it ends open, on the
// dominant); two candidate ANSWER phrases are shown as notation. Tapping
// a card plays question + that answer; the fitting answer closes on the
// tonic. SRI: 'composition.answer.c_major'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

class QuestionAnswerScreen extends StatefulWidget {
  const QuestionAnswerScreen({super.key});

  @override
  State<QuestionAnswerScreen> createState() => _QuestionAnswerScreenState();
}

class _QuestionAnswerScreenState extends State<QuestionAnswerScreen>
    with QuizRoundMixin {
  final _random = Random();
  // One highlighter per staff so the question lights during the question and
  // the tapped answer lights during the answer, across one combined playback.
  final _qPb = ScorePlayback();
  final _aPb = [ScorePlayback(), ScorePlayback()];

  late List<Pitch> _question; // ends on G4 (dominant) — open
  late List<List<Pitch>> _answers; // 2 candidates, shuffled
  late int _correctCard; // the one ending on the tonic
  int? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 8;

  @override
  void dispose() {
    _qPb.dispose();
    for (final p in _aPb) {
      p.dispose();
    }
    super.dispose();
  }

  // The phrases themselves are the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  String get gameType => 'question_answer';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playQuestion());
  }

  List<Pitch> _phrase({required int endPosition}) {
    var position = 3 + _random.nextInt(3);
    final phrase = <Pitch>[];
    for (var i = 0; i < 3; i++) {
      phrase.add(Clef.treble.pitchAt(position));
      position = (position + [-1, 1, 1, 2][_random.nextInt(4)]).clamp(1, 8);
    }
    phrase.add(Clef.treble.pitchAt(endPosition));
    return phrase;
  }

  @override
  void prepareRound() {
    _question = _phrase(endPosition: 2); // ends on G4 — asks
    final closing = _phrase(endPosition: 5); // ends on C5 — answers
    final open = _phrase(endPosition: [6, 4][_random.nextInt(2)]);
    _answers = [closing, open]..shuffle(_random);
    _correctCard = _answers.indexOf(closing);
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playQuestion();
  }

  void _playQuestion() {
    final seq = [
      for (var i = 0; i < _question.length; i++)
        (_question[i].midiNumber, i == _question.length - 1 ? 700 : 400),
    ];
    context.read<AudioService>().playSequence(seq);
    // Light the question notes (Score.simple ids them e0, e1, … in order).
    _qPb.play([
      for (var i = 0; i < seq.length; i++) (ids: {'e$i'}, ms: seq[i].$2),
    ]);
  }

  void _playQuestionAndAnswer(int index) {
    final answer = _answers[index];
    context.read<AudioService>().playSequence([
      for (final p in _question) (p.midiNumber, 380),
      for (var i = 0; i < answer.length; i++)
        (answer[i].midiNumber, i == answer.length - 1 ? 800 : 380),
    ]);
    // Question staff lights during the question, then clears.
    _qPb.play([
      for (var i = 0; i < _question.length; i++) (ids: {'e$i'}, ms: 380),
    ]);
    // The tapped answer staff waits out the question (empty highlight), then
    // lights its notes as they sound.
    _aPb[index].play([
      (ids: <String>{}, ms: _question.length * 380),
      for (var i = 0; i < answer.length; i++)
        (ids: {'e$i'}, ms: i == answer.length - 1 ? 800 : 380),
    ]);
  }

  Score _phraseScore(List<Pitch> phrase) => Score.simple(
        notes: phrase
            .asMap()
            .entries
            .map(
              (e) =>
                  '${e.value.step.name}${e.value.octave}${e.key == phrase.length - 1 ? ':h' : e.key == 0 ? ':q' : ''}',
            )
            .join(' '),
      );

  void _onCardTap(int index) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = index == _correctCard;
    _playQuestionAndAnswer(index);

    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('composition.answer.c_major', correct);
    }

    setState(() {
      _tapped = index;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(
        title: l10n.gameQuestionAnswer,
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playQuestion,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'question_answer',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      correct: _lastAnswer,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.questionAnswerPrompt,
                    ),
                    const SizedBox(height: 8),
                    // The question phrase, always visible.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.help_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: PlayingStaffView(
                                score: _phraseScore(_question),
                                controller: _qPb,
                                staffSpace: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = 0; i < _answers.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: _tapped == null
                                        ? BorderSide.none
                                        : i == _correctCard &&
                                                _tapped == _correctCard
                                            ? const BorderSide(
                                                color: Colors.green,
                                                width: 3,
                                              )
                                            : i == _tapped
                                                ? const BorderSide(
                                                    color: Colors.redAccent,
                                                    width: 3,
                                                  )
                                                : BorderSide.none,
                                  ),
                                  child: InkWell(
                                    onTap: () => _onCardTap(i),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 10),
                                        const Icon(Icons.reply),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Center(
                                            child: PlayingStaffView(
                                              score: _phraseScore(
                                                _answers[i],
                                              ),
                                              controller: _aPb[i],
                                              staffSpace: 8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
