// lib/features/games/scales/mode_ear_screen.dart
//
// "Which Mode?" — a three-way ear game on modal colour. A scale is played
// ascending from a tonic (synthesized, no staff shown) as one of three modes:
// Major (Ionian), natural Minor (Aeolian), or **Dorian**. The child decides
// which one they heard. Dorian is the ear-trap: it is minor-shaped but with a
// RAISED 6th, so it sounds "minor, but a touch brighter" — the whole point of
// the game is to notice that one note. Big replay button for repeated listening.
//
// The scales are built app-side from exact semitone step patterns, so the played
// pitches reflect the mode precisely (the raised 6th is what separates Dorian
// from natural minor).
//
// SRI: 'scales.mode.<major|minor|dorian>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// The three modes the game distinguishes, with their ascending semitone step
/// patterns (tonic to octave). Dorian = natural minor with a raised 6th.
enum Mode {
  major([0, 2, 4, 5, 7, 9, 11, 12]),
  minor([0, 2, 3, 5, 7, 8, 10, 12]),
  dorian([0, 2, 3, 5, 7, 9, 10, 12]);

  const Mode(this.steps);

  /// Semitone offsets from the tonic, ascending through the octave.
  final List<int> steps;
}

class ModeEarScreen extends StatefulWidget {
  const ModeEarScreen({super.key});

  @override
  State<ModeEarScreen> createState() => _ModeEarScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ModeEarTester {
  /// The mode currently playing — the correct answer.
  Mode get answer;
  bool get isFinished;
}

class _ModeEarScreenState extends State<ModeEarScreen>
    with QuizRoundMixin
    implements ModeEarTester {
  final _random = Random();

  static const _roots = [Step.c, Step.d, Step.e, Step.f, Step.g, Step.a];
  static const _modes = [Mode.major, Mode.minor, Mode.dorian];

  late Step _root;
  late Mode _mode;
  Mode? _tapped;
  bool? _lastAnswer;

  @override
  Mode get answer => _mode;
  @override
  bool get isFinished => finished;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'mode_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playScale());
  }

  @override
  void prepareRound() {
    _root = _roots[_random.nextInt(_roots.length)];
    _mode = _modes[_random.nextInt(_modes.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playScale();
  }

  void _playScale() {
    final base = Pitch(_root).midiNumber;
    final notes = [for (final s in _mode.steps) (base + s, 300)];
    context.read<AudioService>().playSequence(notes);
  }

  String _labelFor(AppLocalizations l, Mode m) => switch (m) {
        Mode.major => l.modeMajor,
        Mode.minor => l.modeMinor,
        Mode.dorian => l.modeDorian,
      };

  void _onAnswer(Mode choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _mode;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'scales.mode.${_mode.name}',
            correct,
          );
    }

    if (correct) {
      _playScale();
    } else {
      context.read<AudioService>().playWrong();
    }

    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  bool get playFeedbackSounds => false; // we replay the scale / buzz ourselves

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameMode),
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
                      prompt: l10n.modePrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: IconButton.filledTonal(
                          iconSize: 96,
                          padding: const EdgeInsets.all(32),
                          icon: const Icon(Icons.volume_up),
                          tooltip: l10n.listenAgain,
                          onPressed: _playScale,
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
                    AnswerGrid(
                      children: [
                        for (final m in _modes)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : m == _mode && _tapped == _mode
                                      ? Colors.green
                                      : m == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(m),
                            child: Text(_labelFor(l10n, m)),
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
