// lib/features/games/note_reading/accidental_sort_screen.dart
//
// "Sharp or Flat?" — a drag-and-drop sorting game on accidental *signs*: each
// note carries a sharp or a flat, and the child drags it into the ♯ or ♭
// basket. Reading the little sign in front of a note is the skill. A card only
// drops into the correct basket; a wrong drop bounces back and buzzes (the
// no-fail loop). The sort-into-buckets format (like Sort the Beats / High or
// Low?), on the sharp/flat dimension (docs/PLAN.md sort backlog).
//
// SRI: 'accidentals.sign.<sharp|flat>'.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

const _whole = NoteDuration(DurationBase.whole);

class AccidentalSortScreen extends StatefulWidget {
  const AccidentalSortScreen({super.key});

  static const cardCount = 4;
  static const _buckets = [true, false]; // true = sharp, false = flat

  @override
  State<AccidentalSortScreen> createState() => _AccidentalSortScreenState();
}

class _AccidentalSortScreenState extends State<AccidentalSortScreen>
    with QuizRoundMixin {
  final _random = Random();

  late List<Pitch> _cards; // one note per card, each with an accidental
  late List<bool> _sharp; // card index → carries a sharp (else a flat)
  late List<bool> _placed;
  final Map<bool, List<Pitch>> _binned = {true: [], false: []};
  final Set<int> _recorded = {};
  bool? _lastDropOk;

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'accidental_sort';

  // Drops give their own feedback (the note sounds on a correct drop, a buzz on
  // a miss); no generic blips.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Notes sit comfortably on the treble staff; each gets a sharp or a flat.
    // Guarantee at least one of each sign so both baskets are always in play.
    final signs = <bool>[true, false];
    while (signs.length < AccidentalSortScreen.cardCount) {
      signs.add(_random.nextBool());
    }
    signs.shuffle(_random);

    _cards = [
      for (final sharp in signs)
        () {
          final base = Clef.treble.pitchAt(1 + _random.nextInt(7)); // F4..E5
          return Pitch(base.step, alter: sharp ? 1 : -1, octave: base.octave);
        }(),
    ];
    _sharp = signs;
    _placed = List.filled(AccidentalSortScreen.cardCount, false);
    _binned
      ..[true]!.clear()
      ..[false]!.clear();
    _recorded.clear();
    _lastDropOk = null;
  }

  void _onAccept(int cardIndex, bool bucketSharp) {
    // Only ever called for the correct basket (see onWillAccept).
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'accidentals.sign.${bucketSharp ? 'sharp' : 'flat'}',
            true,
          );
    }
    context
        .read<AudioService>()
        .playMidiNote(_cards[cardIndex].midiNumber, ms: 400);
    setState(() {
      _placed[cardIndex] = true;
      _binned[bucketSharp]!.add(_cards[cardIndex]);
      _lastDropOk = true;
    });
    if (_placed.every((p) => p)) resolveAnswer(correct: true);
  }

  void _onMiss(int cardIndex) {
    context.read<AudioService>().playWrong();
    if (_recorded.add(cardIndex)) {
      context.read<SriService>().recordResponse(
            'accidentals.sign.${_sharp[cardIndex] ? 'sharp' : 'flat'}',
            false,
          );
    }
    setState(() {
      answeredWrong = true;
      _lastDropOk = false;
    });
  }

  Score _score(Pitch p) => Score(
        clef: Clef.treble,
        measures: [
          Measure([NoteElement.note(p, _whole, id: 'n')]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameAccidentalSort),
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
                      correct: finished ? true : _lastDropOk,
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.accidentalSortPrompt,
                    ),
                    const SizedBox(height: 16),
                    // Card pool.
                    SizedBox(
                      height: 120,
                      child: Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          children: [
                            for (var i = 0; i < _cards.length; i++)
                              if (!_placed[i])
                                Draggable<int>(
                                  data: i,
                                  feedback: _NoteCard(
                                    score: _score(_cards[i]),
                                    dragging: true,
                                  ),
                                  childWhenDragging: const SizedBox(
                                    width: 84,
                                    height: 104,
                                  ),
                                  onDraggableCanceled: (_, __) => _onMiss(i),
                                  child: _NoteCard(score: _score(_cards[i])),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final sharp in AccidentalSortScreen._buckets)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: DragTarget<int>(
                                onWillAcceptWithDetails: (d) =>
                                    _sharp[d.data] == sharp,
                                onAcceptWithDetails: (d) =>
                                    _onAccept(d.data, sharp),
                                builder: (context, candidate, __) => _Bucket(
                                  sharp: sharp,
                                  label: sharp
                                      ? l10n.accidentalSharpLabel
                                      : l10n.accidentalFlatLabel,
                                  hovering: candidate.isNotEmpty,
                                  contents: _binned[sharp] ?? const [],
                                  scoreOf: _score,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: finished ? true : _lastDropOk),
                  ],
                ),
              ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Score score;
  final bool dragging;

  const _NoteCard({required this.score, this.dragging = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 84,
        height: 104,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dragging
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: StaffView(score: score, staffSpace: 7, theme: kidsScoreTheme),
      ),
    );
  }
}

class _Bucket extends StatelessWidget {
  final bool sharp;
  final String label;
  final bool hovering;
  final List<Pitch> contents;
  final Score Function(Pitch) scoreOf;

  const _Bucket({
    required this.sharp,
    required this.label,
    required this.hovering,
    required this.contents,
    required this.scoreOf,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 184,
      decoration: BoxDecoration(
        color:
            hovering ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hovering ? scheme.primary : scheme.outlineVariant,
          width: hovering ? 3 : 2,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Text(
            // The SMuFL-free glyph is fine for a big basket label.
            '$label  ${sharp ? '♯' : '♭'}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final p in contents)
                  SizedBox(
                    width: 64,
                    height: 70,
                    child: StaffView(
                      score: scoreOf(p),
                      staffSpace: 6,
                      theme: kidsScoreTheme,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
