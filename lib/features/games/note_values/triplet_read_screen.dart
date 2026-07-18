// lib/features/games/note_values/triplet_read_screen.dart
//
// "Even or Triplet?" — reading how a beat is split. Two eighths cut a beat into
// two even halves ("1-and"); a triplet squeezes THREE equal notes into the same
// beat ("1-and-a", or "trip-o-let"), marked with a little 3. The child reads/hears
// the first beat and decides. Binary staff-read, no-fail loop.
//
// The triplet is a real `TupletSpan(0, 2, actual: 3, normal: 2)` over three
// eighths, so the engraver draws the bracket + 3; playback fits 3 notes in the
// beat (200 ms each) vs 2 even (300 ms), so the difference is heard.
//
// SRI: 'note_values.tuplet.<even|triplet>'.

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

const _eighth = NoteDuration(DurationBase.eighth);
const _quarter = NoteDuration(DurationBase.quarter);
const _half = NoteDuration(DurationBase.half);

class TripletReadScreen extends StatefulWidget {
  const TripletReadScreen({super.key});

  @override
  State<TripletReadScreen> createState() => _TripletReadScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class TripletReadTester {
  /// Whether the shown beat is a triplet — the correct answer.
  bool get answerTriplet;
  bool get isFinished;
}

class _TripletReadScreenState extends State<TripletReadScreen>
    with QuizRoundMixin
    implements TripletReadTester {
  @override
  bool get answerTriplet => _triplet;
  @override
  bool get isFinished => finished;

  final _random = Random();
  final _pb = ScorePlayback();

  @override
  void dispose() {
    _pb.dispose();
    super.dispose();
  }

  late bool _triplet;
  late Pitch _note;
  bool? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'triplet_read';

  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _triplet = _random.nextBool();
    _note = Clef.treble.pitchAt(2 + _random.nextInt(5));
    _tapped = null;
    _lastAnswer = null;
  }

  // Beat 1 split: two even eighths, or a triplet of three eighths (marked 3);
  // the rest of the bar is filled with rests so the split reads on its own.
  Score get _cardScore => _triplet
      ? Score(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure(
              [
                NoteElement.note(_note, _eighth, id: 't0'),
                NoteElement.note(_note, _eighth, id: 't1'),
                NoteElement.note(_note, _eighth, id: 't2'),
                const RestElement(_quarter),
                const RestElement(_half),
              ],
              tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2)],
            ),
          ],
        )
      : Score(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              NoteElement.note(_note, _eighth, id: 'e0'),
              NoteElement.note(_note, _eighth, id: 'e1'),
              const RestElement(_quarter),
              const RestElement(_half),
            ]),
          ],
        );

  List<(int, int)> get _phrase {
    final m = _note.midiNumber;
    return _triplet ? [(m, 200), (m, 200), (m, 200)] : [(m, 300), (m, 300)];
  }

  void _onAnswer(bool triplet) {
    if (_lastAnswer == true) return;
    final correct = triplet == _triplet;
    final audio = context.read<AudioService>();
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'note_values.tuplet.${_triplet ? 'triplet' : 'even'}',
            correct,
          );
    }
    if (correct) {
      audio.playSequence(_phrase);
      _pb.play([
        for (var i = 0; i < _phrase.length; i++)
          (ids: {_triplet ? 't$i' : 'e$i'}, ms: _phrase[i].$2),
      ]);
    } else {
      audio.playWrong();
    }
    setState(() {
      _tapped = triplet;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameTripletRead),
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
                      prompt: l10n.tripletReadPrompt,
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
                    Row(
                      children: [
                        for (final trip in const [false, true])
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
                                      : trip == _triplet && _tapped == _triplet
                                          ? Colors.green
                                          : trip == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  trip ? Icons.looks_3 : Icons.looks_two,
                                ),
                                onPressed: () => _onAnswer(trip),
                                label: Text(
                                  trip
                                      ? l10n.tripletReadTriplet
                                      : l10n.tripletReadEven,
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
