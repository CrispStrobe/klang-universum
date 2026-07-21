// lib/features/games/chords/seventh_ear_screen.dart
//
// "Which Seventh?" — an ear game on seventh-chord QUALITY (the step past "Triad
// or Seventh?"). A seventh chord is played (arpeggio then block, synthesized, no
// staff) and the child names its flavour: Major 7, Dominant 7, or Minor 7 — with
// the Half-diminished (m7b5) added at 2★. Each quality's colour comes from which
// third + which seventh it stacks, so this trains the ear to hear both at once.
//
// Chords are voiced from the shared chord-quality vocabulary (a root pitch + the
// quality's semitone intervals), so a Cmaj7 really is C-E-G-B, a C7 C-E-G-Bb, a
// Cm7 C-Eb-G-Bb, and a Cm7b5 C-Eb-Gb-Bb.
//
// SRI: 'chords.hear.seventh.<maj7|dom7|min7|hdim7>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The seventh-chord qualities this game drills, with their intervals (semitones
/// from the root) and the SRI/id token.
enum SeventhKind {
  major7('maj7', [0, 4, 7, 11]),
  dominant7('dom7', [0, 4, 7, 10]),
  minor7('min7', [0, 3, 7, 10]),
  halfDim7('hdim7', [0, 3, 6, 10]);

  const SeventhKind(this.token, this.intervals);
  final String token;
  final List<int> intervals;
}

class SeventhEarScreen extends StatefulWidget {
  const SeventhEarScreen({super.key});

  @override
  State<SeventhEarScreen> createState() => _SeventhEarScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class SeventhEarTester {
  /// The correct seventh quality this round.
  SeventhKind get answer;
  bool get isFinished;
}

class _SeventhEarScreenState extends State<SeventhEarScreen>
    with QuizRoundMixin
    implements SeventhEarTester {
  final _random = Random();

  // The three clearest qualities at 1★; the half-diminished joins at 2★.
  static const _base = [
    SeventhKind.major7,
    SeventhKind.dominant7,
    SeventhKind.minor7,
  ];
  static const _all = SeventhKind.values;

  // A comfortable root range (C4..A4) so every voicing stays mid-register.
  static const _rootLo = 60, _rootHi = 69;

  late int _root; // midi of the chord root
  late SeventhKind _kind;
  bool _fourWay = false;
  SeventhKind? _tapped;
  bool? _lastAnswer;

  @override
  SeventhKind get answer => _kind;
  @override
  bool get isFinished => finished;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'seventh_ear';

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playChord());
  }

  @override
  void prepareRound() {
    _fourWay = context.read<ProgressService>().starsFor(gameType) >= 2;
    final choices = _fourWay ? _all : _base;
    _root = _rootLo + _random.nextInt(_rootHi - _rootLo + 1);
    _kind = choices[_random.nextInt(choices.length)];
    _tapped = null;
    _lastAnswer = null;
    if (round > 0) _playChord();
  }

  void _playChord() {
    final midis = [for (final i in _kind.intervals) _root + i];
    context.read<AudioService>().playArpeggioThenChord(midis);
  }

  void _onAnswer(SeventhKind choice) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = choice == _kind;

    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'chords.hear.seventh.${_kind.token}',
            correct,
          );
    }

    setState(() {
      _tapped = choice;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  static String _labelFor(AppLocalizations l, SeventhKind k) => switch (k) {
        SeventhKind.major7 => l.seventhMajorLabel,
        SeventhKind.dominant7 => l.seventhDominantLabel,
        SeventhKind.minor7 => l.seventhMinorLabel,
        SeventhKind.halfDim7 => l.seventhHalfDimLabel,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final choices = _fourWay ? _all : _base;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameSeventhEar),
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
                      prompt: l10n.seventhEarPrompt,
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
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final k in choices)
                          SizedBox(
                            width: 160,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                backgroundColor: _tapped == null
                                    ? null
                                    : k == _kind && _tapped == _kind
                                        ? Colors.green
                                        : k == _tapped
                                            ? Colors.redAccent
                                            : null,
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              onPressed: () => _onAnswer(k),
                              child: Text(_labelFor(l10n, k)),
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
