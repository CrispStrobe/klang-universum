// lib/features/games/guitar/power_chord_screen.dart
//
// "Power Chords" — a power chord is just a ROOT + its FIFTH (a movable two-note
// "5" shape, the backbone of rock/pop guitar). A shape is shown as two dots on
// the fretboard; the child names it (e.g. G5) from four choices, reading the
// root's position. A correct answer plays the chord (root + fifth).
//
// SRI: 'guitar.power.<name>'.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/guitar/guitar_tab.dart';
import 'package:comet_beat/features/games/note_reading/note_names.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:provider/provider.dart';

/// Frets shown; a root at fret 1..5 plus its fifth (root+2) stays within 0..7.
const int _maxFret = 7;

class PowerChordScreen extends StatefulWidget {
  const PowerChordScreen({super.key});

  @override
  State<PowerChordScreen> createState() => _PowerChordScreenState();
}

class _PowerChordScreenState extends State<PowerChordScreen>
    with QuizRoundMixin {
  int _round = 0; // deterministic (test-stable) shape rotation

  // The two fretted notes of the shape.
  late int _rootString;
  late int _rootFret;
  late int _fifthString;
  late int _fifthFret;
  late int _correctPc; // the root's pitch class (0..11)
  late List<int> _optionPcs;
  int? _tappedPc;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  @override
  String get gameType => 'power_chord';

  // The chord itself is the audio feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  int _midiAt(int string, int fret) =>
      kGuitarTuning.strings[string].midiNumber + fret;

  /// A pitch class's name + the "5" suffix (honours the note-name style; sharps
  /// get a ♯). 0 = C … 11 = B.
  String _nameOf(int pc) {
    final p = Pitch.fromMidi(60 + pc % 12);
    return '${noteNameFor(context, p.step)}${p.alter == 1 ? '♯' : ''}5';
  }

  @override
  void prepareRound() {
    // Alternate low-E-rooted (string 5) and A-rooted (string 4) shapes; the
    // fifth sits one string higher in pitch (lower index), two frets up.
    _rootString = _round.isEven ? 5 : 4;
    _rootFret = 1 + (_round * 2) % 5; // 1..5, varied + stable
    _fifthString = _rootString - 1;
    _fifthFret = _rootFret + 2;
    _round++;

    // Pitch classes only here — display names need context (see [build]).
    _correctPc = _midiAt(_rootString, _rootFret) % 12;
    final opts = <int>{_correctPc};
    for (var off = 1; opts.length < 4; off++) {
      opts.add((_correctPc + off) % 12); // other roots, all "5" chords
    }
    _optionPcs = opts.toList()..shuffle();
    _tappedPc = null;
    _lastAnswer = null;
  }

  void _onAnswer(int pc) {
    if (_lastAnswer == true) return; // round already resolved
    final correct = pc == _correctPc;
    final audio = context.read<AudioService>();

    if (_tappedPc == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('guitar.power.pc$_correctPc', correct);
    }
    if (correct) {
      final root = _midiAt(_rootString, _rootFret);
      audio.playMidiChord([root, root + 7]); // root + perfect fifth
    } else {
      audio.playWrong();
    }
    setState(() {
      _tappedPc = pc;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  Color? _buttonColor(int pc) {
    if (_tappedPc == null) return null;
    if (pc == _correctPc) return Colors.green;
    if (pc == _tappedPc) return Colors.redAccent;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final strings = kGuitarTuning.strings;

    Widget cell(int s, int f) {
      final isRoot = s == _rootString && f == _rootFret;
      final isFifth = s == _fifthString && f == _fifthFret;
      return Expanded(
        child: Container(
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isRoot
                ? scheme.primary
                : isFifth
                    ? scheme.tertiary
                    : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: isRoot
              ? Text(
                  'R',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : isFifth
                  ? Text(
                      '5',
                      style: TextStyle(
                        color: scheme.onTertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
        ),
      );
    }

    return Scaffold(
      appBar: GameAppBar(title: l10n.gamePowerChord),
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
                      prompt: l10n.powerChordPrompt,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const SizedBox(width: 30),
                                  for (var f = 0; f <= _maxFret; f++)
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          '$f',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              for (var s = 0; s < strings.length; s++)
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 30,
                                      child: Text(
                                        noteNameFor(context, strings[s].step),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium,
                                      ),
                                    ),
                                    for (var f = 0; f <= _maxFret; f++)
                                      cell(s, f),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 16),
                    AnswerGrid(
                      children: [
                        for (final pc in _optionPcs)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _buttonColor(pc),
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(pc),
                            child: Text(_nameOf(pc)),
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
