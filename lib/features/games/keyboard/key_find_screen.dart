// lib/features/games/keyboard/key_find_screen.dart
//
// "Taste finden" — a note on the treble staff, a piano keyboard below:
// tap the matching key. The bridge from notation to keyboard geography.
// Every tapped key sounds, so misses teach too.
//
// SRI: 'keyboard.find.<step><octave>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/services/progress_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/piano_keyboard.dart';
import '../widgets/game_widgets.dart';

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

  @override
  void prepareRound() {
    // Staff naturals E4..F5 (positions 0..8) — all inside the C4..G5 keys.
    _target = Clef.treble.pitchAt(_random.nextInt(9));
    _tappedMidi = null;
    _lastAnswer = null;
  }

  void _onKeyTap(int midi) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = midi == _target.midiNumber;
    context.read<AudioService>().playMidiNote(midi, ms: 550);

    if (_tappedMidi == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'keyboard.find.${_target.step.name}${_target.octave}',
            correct,
          );
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
    final showLabels =
        context.read<ProgressService>().starsFor('key_find') < 2;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameKeyFind)),
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
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.keyFindPrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: StaffView(
                              score: Score.simple(
                                notes:
                                    '${_target.step.name}${_target.octave}:w',
                              ),
                              staffSpace: 12,
                              theme: PartituraTheme.kids,
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
                        startMidi: 60, // C4..G5
                        whiteKeyCount: 12,
                        showLabels: showLabels,
                        onKeyTap: _onKeyTap,
                        keyColors: {
                          if (_tappedMidi != null)
                            _tappedMidi!: _lastAnswer!
                                ? Colors.green
                                : Colors.redAccent,
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
