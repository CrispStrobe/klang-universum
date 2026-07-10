// lib/features/games/note_values/rhythm_tap_screen.dart
//
// "Rhythmus-Echo" — a one-measure rhythm is played (and shown as notation);
// the child taps it back on a big pad. Timing is compared onset-by-onset
// relative to the first tap, so absolute start doesn't matter.
//
// SRI: 'note_values.rhythm.p<index>'.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart' show Score, StaffView, TimeSignature;
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../core/services/sri_service.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/game_widgets.dart';

class _Pattern {
  /// Note durations in beats (4/4, sums to 4).
  final List<double> beats;
  final String dsl; // for notation display, on a fixed pitch

  const _Pattern(this.beats, this.dsl);

  /// Relative onset times in beats (first note at 0).
  List<double> get onsets {
    final result = <double>[];
    var t = 0.0;
    for (final b in beats) {
      result.add(t);
      t += b;
    }
    return result;
  }
}

const _patterns = <_Pattern>[
  _Pattern([1, 1, 1, 1], 'g4:q g4 g4 g4'),
  _Pattern([1, 1, 2], 'g4:q g4 g4:h'),
  _Pattern([2, 1, 1], 'g4:h g4:q g4'),
  _Pattern([1, 0.5, 0.5, 1, 1], 'g4:q g4:e g4 g4:q g4'),
  _Pattern([0.5, 0.5, 1, 0.5, 0.5, 1], 'g4:e g4 g4:q g4:e g4 g4:q'),
];

class RhythmTapScreen extends StatefulWidget {
  const RhythmTapScreen({super.key});

  static const beatMs = 600; // 100 BPM
  static const toleranceMs = 170;

  @override
  State<RhythmTapScreen> createState() => _RhythmTapScreenState();
}

class _RhythmTapScreenState extends State<RhythmTapScreen>
    with QuizRoundMixin {
  final _random = Random();

  late int _patternIndex;
  _Pattern get _pattern => _patterns[_patternIndex];
  final List<int> _tapTimesMs = [];
  final Stopwatch _stopwatch = Stopwatch();
  bool? _lastAnswer;

  @override
  int get totalRounds => 8;

  @override
  String get gameType => 'rhythm_tap';

  // Taps click on their own; blips would muddle the rhythm.
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPattern());
  }

  @override
  void prepareRound() {
    _patternIndex = _random.nextInt(_patterns.length);
    _tapTimesMs.clear();
    _stopwatch
      ..stop()
      ..reset();
    _lastAnswer = null;
    if (round > 0) _playPattern();
  }

  void _playPattern() {
    context.read<AudioService>().playSequence([
      for (final b in _pattern.beats)
        (79, (b * RhythmTapScreen.beatMs).round()), // G5 taps
    ]);
  }

  void _onTap() {
    if (_lastAnswer != null) return; // evaluating/resolved
    context.read<AudioService>().playMidiNote(79, ms: 150);

    if (_tapTimesMs.isEmpty) _stopwatch.start();
    setState(() => _tapTimesMs.add(_stopwatch.elapsedMilliseconds));

    if (_tapTimesMs.length == _pattern.beats.length) {
      _evaluate();
    }
  }

  void _evaluate() {
    final expected = _pattern.onsets
        .map((b) => (b * RhythmTapScreen.beatMs).round())
        .toList();
    final t0 = _tapTimesMs.first;
    var correct = true;
    for (var i = 0; i < expected.length; i++) {
      final relative = _tapTimesMs[i] - t0;
      if ((relative - expected[i]).abs() > RhythmTapScreen.toleranceMs) {
        correct = false;
        break;
      }
    }

    context
        .read<SriService>()
        .recordResponse('note_values.rhythm.p$_patternIndex', correct);
    final audio = context.read<AudioService>();
    correct ? audio.playCorrect() : audio.playWrong();

    setState(() => _lastAnswer = correct);
    if (correct) {
      resolveAnswer(correct: true);
    } else {
      // Full retry: wrong rhythm resets the taps after a beat.
      resolveAnswer(correct: false);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() {
          _tapTimesMs.clear();
          _stopwatch
            ..stop()
            ..reset();
          _lastAnswer = null;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gameRhythmTap),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: l10n.listenAgain,
            onPressed: _playPattern,
          ),
        ],
      ),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: 'rhythm_tap',
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RoundHeader(
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.rhythmTapPrompt,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: StaffView(
                          score: Score.simple(
                            timeSignature: TimeSignature.fourFour,
                            notes: _pattern.dsl,
                          ),
                          staffSpace: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pattern.beats.length; i++)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              i < _tapTimesMs.length
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 16,
                              color:
                                  Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(32),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(32),
                            onTap: _onTap,
                            child: Center(
                              child: Text(
                                l10n.tapHere,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
