// lib/features/games/keyboard/key_find_screen.dart
//
// "Taste finden" — a note on the treble staff, a piano keyboard below:
// tap the matching key. The bridge from notation to keyboard geography.
// Every tapped key sounds, so misses teach too.
//
// SRI: 'keyboard.find.<step><octave>'.

import 'dart:math';

import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
import 'package:provider/provider.dart';

class KeyFindScreen extends StatefulWidget {
  const KeyFindScreen({super.key});

  @override
  State<KeyFindScreen> createState() => _KeyFindScreenState();
}

class _KeyFindScreenState extends State<KeyFindScreen> with QuizRoundMixin {
  final _random = Random();

  late Pitch _target;
  int? _tappedMidi;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'key_find';

  // Tapped keys sound on their own.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  // Black-key targets, unlocked at 3 stars (all within C4..G5).
  static const _alteredTargets = [
    Pitch(Step.f, alter: 1), // F#4
    Pitch(Step.g, alter: 1), // G#4
    Pitch(Step.b, alter: -1), // Bb4
    Pitch(Step.c, alter: 1, octave: 5), // C#5
    Pitch(Step.e, alter: -1, octave: 5), // Eb5
  ];

  @override
  void prepareRound() {
    // Staff naturals E4..F5 (positions 0..8) — all inside the C4..G5 keys.
    // At 3 stars, every third round targets a black key (accidental!).
    final stars = context.read<ProgressService>().starsFor('key_find');
    _target = (stars >= 3 && _random.nextInt(3) == 0)
        ? _alteredTargets[_random.nextInt(_alteredTargets.length)]
        : Clef.treble.pitchAt(_random.nextInt(9));
    _tappedMidi = null;
    _lastAnswer = null;
  }

  String get _targetToken {
    final accidental = switch (_target.alter) { 1 => '#', -1 => 'b', _ => '' };
    return '${_target.step.name}$accidental${_target.octave}';
  }

  void _onKeyTap(int midi) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = midi == _target.midiNumber;
    context.read<AudioService>().playMidiNote(midi, ms: 550);

    if (_tappedMidi == null || !answeredWrong) {
      // Token includes the accidental, so F#4 is a distinct item from F4.
      context
          .read<SriService>()
          .recordResponse('keyboard.find.$_targetToken', correct);
    }

    setState(() {
      _tappedMidi = midi;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);

    if (!correct) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted || _lastAnswer == true) return;
        setState(() => _tappedMidi = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Beginners (0-1 stars) get letter labels on the keys.
    final showLabels = context.read<ProgressService>().starsFor('key_find') < 2;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameKeyFind),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'key_find',
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
                      prompt: l10n.keyFindPrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: StaffView(
                              score: Score.simple(notes: '$_targetToken:w'),
                              staffSpace: 12,
                              theme: kidsScoreTheme,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 170,
                      child: PianoKeyboard(
                        showLabels: showLabels,
                        onKeyTap: _onKeyTap,
                        keyColors: {
                          if (_tappedMidi != null)
                            _tappedMidi!:
                                _lastAnswer! ? Colors.green : Colors.redAccent,
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
