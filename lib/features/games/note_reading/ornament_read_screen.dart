// lib/features/games/note_reading/ornament_read_screen.dart
//
// "Which Ornament?" — reading the little signs that tell you to decorate a note.
// A trill (tr) shakes fast between the note and the one above; a mordent (a small
// squiggle) is one quick flick up and back; a turn (an S on its side) curls
// around the note (above–note–below–note). The child reads the sign over the note
// and names it. Big staff card, three tap buttons, no-fail loop.
//
// SRI: 'note_reading.ornament.<trill|mordent|turn>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/features/games/widgets/playing_staff.dart';
import 'package:comet_beat/features/games/widgets/reading_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _half = NoteDuration(DurationBase.half);
const _ornaments = [Ornament.trill, Ornament.mordent, Ornament.turn];

class OrnamentReadScreen extends StatefulWidget {
  const OrnamentReadScreen({super.key});

  @override
  State<OrnamentReadScreen> createState() => _OrnamentReadScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class OrnamentReadTester {
  /// The ornament shown — the correct answer.
  Ornament get answer;
  bool get isFinished;
}

class _OrnamentReadScreenState extends State<OrnamentReadScreen>
    with QuizRoundMixin
    implements OrnamentReadTester {
  @override
  Ornament get answer => _ornament;
  @override
  bool get isFinished => finished;

  final _random = Random();
  final _pb = ScorePlayback();

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  late Ornament _ornament;
  late Pitch _note;
  Ornament? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'ornament_read';

  @override
  bool get playFeedbackSounds => false;

  String _name(Ornament o) => switch (o) {
        Ornament.trill => 'trill',
        Ornament.mordent => 'mordent',
        Ornament.turn => 'turn',
        _ => o.name,
      };

  String _label(AppLocalizations l, Ornament o) => switch (o) {
        Ornament.trill => l.ornamentTrill,
        Ornament.mordent => l.ornamentMordent,
        Ornament.turn => l.ornamentTurn,
        _ => o.name,
      };

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _ornament = _ornaments[_random.nextInt(_ornaments.length)];
    _note = Clef.treble.pitchAt(3 + _random.nextInt(4)); // 3..6, room above
    _tapped = null;
    _lastAnswer = null;
  }

  Score get _cardScore => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(_note, _half, id: 'n', ornament: _ornament),
          ]),
        ],
      );

  // A tiny flourish so the ornament is heard, not just seen.
  List<(int, int)> get _phrase {
    final m = _note.midiNumber;
    return switch (_ornament) {
      Ornament.trill => [(m, 90), (m + 2, 90), (m, 90), (m + 2, 90), (m, 240)],
      Ornament.mordent => [(m, 110), (m + 2, 110), (m, 400)],
      Ornament.turn => [(m + 2, 140), (m, 140), (m - 1, 140), (m, 360)],
      _ => [(m, 500)],
    };
  }

  void _onAnswer(Ornament choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _ornament;
    final audio = context.read<AudioService>();
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'note_reading.ornament.${_name(_ornament)}',
            correct,
          );
    }
    if (correct) {
      audio.playSequence(_phrase);
      // One shown note ('n'); keep it lit through the whole flourish.
      _pb.play([
        for (final n in _phrase) (ids: {'n'}, ms: n.$2),
      ]);
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

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameOrnamentRead),
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
                      prompt: l10n.ornamentReadPrompt,
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
                            child: ReadingStaffView(
                              score: _cardScore,
                              staffSpace: 14,
                              playback: _pb,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final o in _ornaments)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : o == _ornament
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
                            child: Text(_label(l10n, o)),
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
