// lib/features/games/composition/form_read_screen.dart
//
// "Label the Form" — hearing and seeing the SHAPE of a piece. Music is built from
// sections; when a tune comes back it's the same letter, when a new tune arrives
// it's a new letter. So "tune, different tune, tune again" is the form A-B-A. The
// child hears the sections (each a short motif) shown as a coloured timeline —
// same colour = same section — and picks the form. AnaVis in miniature.
//
// Each distinct letter plays a distinct motif; the timeline colours the sections.
// At 1★ the blocks are labelled (guided); at 2★ only the colours show, so the
// child has to work the letters out from the repeat pattern.
//
// SRI: 'composition.form.<FORM>' (e.g. ABA).

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/composition/form_timeline.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Distinct, memorable motifs, one per section letter.
const _motifs = <String, List<int>>{
  'A': [60, 64, 67, 72], // rising arpeggio
  'B': [71, 69, 67, 65], // falling line
  'C': [60, 62, 64, 65], // stepwise up
  'D': [67, 65, 64, 60], // stepwise down
};

const _easyForms = [
  ['A', 'B', 'A'],
  ['A', 'A', 'B'],
  ['A', 'B', 'B'],
  ['A', 'B', 'C'],
];
const _hardForms = [
  ['A', 'A', 'B', 'A'],
  ['A', 'B', 'A', 'B'],
  ['A', 'B', 'A', 'C'],
  ['A', 'B', 'A', 'C', 'A'], // rondo
];

class FormReadScreen extends StatefulWidget {
  const FormReadScreen({super.key});

  @override
  State<FormReadScreen> createState() => _FormReadScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class FormReadTester {
  /// The form string shown, e.g. "ABA" — the correct answer.
  String get answer;
  bool get isFinished;
}

class _FormReadScreenState extends State<FormReadScreen>
    with QuizRoundMixin
    implements FormReadTester {
  @override
  String get answer => _form.join();
  @override
  bool get isFinished => finished;

  final _random = Random();

  late List<String> _form;
  late List<String> _options; // form strings
  String? _tapped;
  bool? _lastAnswer;
  bool _wide = false;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'form_read';

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
    final pool = _wide ? _hardForms : _easyForms;
    _form = pool[_random.nextInt(pool.length)];
    final answerStr = _form.join();
    // Distractors: other forms of the same length.
    final others = pool
        .where((f) => f.length == _form.length && f.join() != answerStr)
        .map((f) => f.join())
        .toList()
      ..shuffle(_random);
    _options = [answerStr, ...others.take(3)]..shuffle(_random);
    _tapped = null;
    _lastAnswer = null;
  }

  List<(int, int)> get _phrase => [
        for (final s in _form)
          for (final m in _motifs[s]!) (m, 320),
      ];

  void _play() => context.read<AudioService>().playSequence(_phrase);

  void _onAnswer(String choice) {
    if (_lastAnswer == true) return;
    final correct = choice == answer;
    final audio = context.read<AudioService>();
    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('composition.form.$answer', correct);
    }
    if (correct) {
      _play();
    } else {
      audio.playWrong();
    }
    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Labels are hidden until answered (or always, once past 1★).
    final reveal = _lastAnswer != null;
    final sections = [
      for (final s in _form) FormSection(s),
    ];

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameFormRead),
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
                      prompt: l10n.formReadPrompt,
                    ),
                    const SizedBox(height: 20),
                    FormTimeline(
                      sections: sections,
                      showLabels: !_wide || reveal,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _play,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l10n.formReadListen),
                    ),
                    const Spacer(),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        for (final o in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : o == answer
                                      ? Colors.green
                                      : o == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(o),
                            child: Text(o),
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
