// lib/features/games/measures/sync_read_screen.dart
//
// "On the Beat or Off?" — reading (and hearing) syncopation. A straight bar puts
// its notes squarely on the beats (1-2-3-4); a syncopated bar pushes them onto
// the off-beats (the "and"s between the beats), which is what gives music its
// kick. The child reads/hears the one-bar rhythm and decides. Binary staff-read,
// no-fail loop.
//
// Straight = four quarters on the beats. Syncopated = an eighth, then quarters,
// then an eighth (½+1+1+1+½ = 4 beats): the inner notes land off the beat, so the
// accents fall between the counts. The playback uses the real note lengths, so
// the syncopation is audible, not just seen.
//
// SRI: 'measures.syncopation.<straight|syncopated>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/features/games/widgets/reading_staff.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

const _eighth = NoteDuration(DurationBase.eighth);
const _quarter = NoteDuration(DurationBase.quarter);

class SyncReadScreen extends StatefulWidget {
  const SyncReadScreen({super.key});

  @override
  State<SyncReadScreen> createState() => _SyncReadScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class SyncReadTester {
  /// Whether the shown bar is syncopated — the correct answer.
  bool get answerSyncopated;
  bool get isFinished;
}

class _SyncReadScreenState extends State<SyncReadScreen>
    with QuizRoundMixin
    implements SyncReadTester {
  @override
  bool get answerSyncopated => _sync;
  @override
  bool get isFinished => finished;

  final _random = Random();

  late bool _sync;
  late Pitch _note; // one comfortable pitch, repeated for the rhythm
  bool? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'sync_read';

  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    _sync = _random.nextBool();
    _note = Clef.treble.pitchAt(2 + _random.nextInt(5)); // 2..6
    _tapped = null;
    _lastAnswer = null;
  }

  // Straight: 4 quarters on the beat. Syncopated: eighth + 3 quarters + eighth,
  // so the middle notes fall on the off-beats.
  Score get _cardScore => Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure(
            _sync
                ? [
                    NoteElement.note(_note, _eighth, id: 'n0'),
                    NoteElement.note(_note, _quarter, id: 'n1'),
                    NoteElement.note(_note, _quarter, id: 'n2'),
                    NoteElement.note(_note, _quarter, id: 'n3'),
                    NoteElement.note(_note, _eighth, id: 'n4'),
                  ]
                : [
                    for (var i = 0; i < 4; i++)
                      NoteElement.note(_note, _quarter, id: 'n$i'),
                  ],
          ),
        ],
      );

  // (midi, ms) with the real note lengths at ~100 bpm, so the ear hears the push.
  List<(int, int)> get _phrase {
    final m = _note.midiNumber;
    return _sync
        ? [(m, 300), (m, 600), (m, 600), (m, 600), (m, 300)]
        : [for (var i = 0; i < 4; i++) (m, 600)];
  }

  void _onAnswer(bool syncopated) {
    if (_lastAnswer == true) return;
    final correct = syncopated == _sync;
    final audio = context.read<AudioService>();
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'measures.syncopation.${_sync ? 'syncopated' : 'straight'}',
            correct,
          );
    }
    if (correct) {
      audio.playSequence(_phrase);
    } else {
      audio.playWrong();
    }
    setState(() {
      _tapped = syncopated;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameSyncRead),
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
                      prompt: l10n.syncReadPrompt,
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
                        for (final sync in const [false, true])
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
                                      : sync == _sync && _tapped == _sync
                                          ? Colors.green
                                          : sync == _tapped
                                              ? Colors.redAccent
                                              : null,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                icon: Icon(
                                  sync ? Icons.stream : Icons.straighten,
                                ),
                                onPressed: () => _onAnswer(sync),
                                label: Text(
                                  sync
                                      ? l10n.syncReadSyncopated
                                      : l10n.syncReadStraight,
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
