// lib/features/games/scales/major_minor_ear_screen.dart
//
// "Dur oder Moll?" — the first ear-training game: a triad is played as an
// arpeggio then a block chord (synthesized, no staff shown); the child
// decides major or minor. Big replay button for repeated listening.
//
// SRI: 'scales.hear.<root>_<quality>'.

import 'dart:math';

import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class MajorMinorEarScreen extends StatefulWidget {
  const MajorMinorEarScreen({super.key});

  @override
  State<MajorMinorEarScreen> createState() => _MajorMinorEarScreenState();
}

class _MajorMinorEarScreenState extends State<MajorMinorEarScreen>
    with QuizRoundMixin {
  final _random = Random();

  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];

  late Step _root;
  late ChordQuality _quality;
  ChordQuality? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'major_minor_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    // Play the first round's chord once the tree is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _playChord());
  }

  @override
  void prepareRound() {
    _root = _roots[_random.nextInt(_roots.length)];
    _quality = _random.nextBool() ? ChordQuality.major : ChordQuality.minor;
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playChord();
  }

  void _playChord() {
    final midis =
        Triad(Pitch(_root), _quality).pitches.map((p) => p.midiNumber).toList();
    context.read<AudioService>().playArpeggioThenChord(midis);
  }

  void _onAnswer(ChordQuality choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _quality;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'scales.hear.${_root.name}_${_quality.name}',
            correct,
          );
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

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameMajorMinorEar),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'major_minor_ear',
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
                      prompt: l10n.listenMajorMinorPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playChord,
                        ),
                      ),
                    ),
                    Text(
                      l10n.listenAgain,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final option in const [
                          ChordQuality.major,
                          ChordQuality.minor,
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  backgroundColor: _tapped == null
                                      ? null
                                      : option == _quality &&
                                              _tapped == _quality
                                          ? Colors.green
                                          : option == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                onPressed: () => _onAnswer(option),
                                child: Text(
                                  option == ChordQuality.major
                                      ? l10n.majorLabel
                                      : l10n.minorLabel,
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
