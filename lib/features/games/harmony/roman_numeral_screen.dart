// lib/features/games/harmony/roman_numeral_screen.dart
//
// "Roman Numerals" (Stufen-Quiz) — read/hear a diatonic triad in a key and name
// its Roman numeral (I, ii, iii, IV, V, vi, vii°). Built on partitura_core's
// new harmonic analysis: the chord is built with `Triad`, then read back with
// `romanNumeralOf(pitches, key)` so the *library* names the numeral — the same
// engine will later carry sevenths, inversions and minor keys.
//
// A step up from the Function Quiz (which only names T/S/D): here every diatonic
// degree is in play. SRI: 'harmony.roman.<symbol>'.

import 'dart:math';

// Material also exports `Step` (Stepper), `Key` (widget key) and `Interval`
// (animation); partitura's win here.
import 'package:flutter/material.dart' hide Interval, Key, Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class RomanNumeralScreen extends StatefulWidget {
  const RomanNumeralScreen({super.key});

  @override
  State<RomanNumeralScreen> createState() => _RomanNumeralScreenState();
}

/// Test handle onto the running game (the state class is private, and the
/// correct answer varies per round).
@visibleForTesting
abstract interface class RomanNumeralTester {
  String get targetSymbol;
  bool get isFinished;
}

class _RomanNumeralScreenState extends State<RomanNumeralScreen>
    with QuizRoundMixin
    implements RomanNumeralTester {
  @override
  String get targetSymbol => _target.symbol;
  @override
  bool get isFinished => finished;

  final _random = Random();

  // Widen with mastery, like the other quizzes.
  static const _easyKeys = [Step.c];
  static const _midKeys = [Step.c, Step.f, Step.g];
  static const _allKeys = [Step.c, Step.g, Step.d, Step.f, Step.b, Step.a];
  static const _easyDegrees = [1, 4, 5]; // the primary triads (T/S/D)
  static const _allDegrees = [1, 2, 3, 4, 5, 6, 7];

  int _stars = 0;

  late Key _key;
  late int _degree;
  late Triad _triad;
  late RomanNumeral _target;
  late List<String> _options; // Roman-numeral choices for this round
  String? _tapped;
  bool? _lastAnswer;

  @override
  int get totalRounds => 10;

  // The chord audio is the feedback.
  @override
  bool get playFeedbackSounds => false;

  @override
  String get gameType => 'roman_numeral';

  List<Step> get _keyPool => _stars >= 2
      ? _allKeys
      : _stars >= 1
          ? _midKeys
          : _easyKeys;

  List<int> get _degreePool => _stars >= 1 ? _allDegrees : _easyDegrees;

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playChord());
  }

  ChordType _chordType(ChordQuality q) => switch (q) {
        ChordQuality.major => ChordType.major,
        ChordQuality.minor => ChordType.minor,
        ChordQuality.diminished => ChordType.diminished,
        ChordQuality.augmented => ChordType.augmented,
      };

  /// The diatonic triad on [degree] of a major [key] (major-key qualities).
  Triad _diatonicTriad(Key key, int degree) {
    final t = key.tonic;
    return switch (degree) {
      1 => Triad(t, ChordQuality.major),
      2 => Triad(t.transposeBy(Interval.majorSecond), ChordQuality.minor),
      3 => Triad(t.transposeBy(Interval.majorThird), ChordQuality.minor),
      4 => Triad(t.transposeBy(Interval.perfectFourth), ChordQuality.major),
      5 => Triad(t.transposeBy(Interval.perfectFifth), ChordQuality.major),
      6 => Triad(t.transposeBy(Interval.majorSixth), ChordQuality.minor),
      _ => Triad(t.transposeBy(Interval.majorSeventh), ChordQuality.diminished),
    };
  }

  /// Let the library name the numeral (falls back to a direct build if the
  /// analyser ever declines a chord).
  String _symbolFor(Key key, int degree) {
    final triad = _diatonicTriad(key, degree);
    return romanNumeralOf(triad.pitches, key)?.symbol ??
        RomanNumeral(degree, ChordType.major, 0).symbol;
  }

  @override
  void prepareRound() {
    _key = Key.major(Pitch(_keyPool[_random.nextInt(_keyPool.length)]));
    _degree = _degreePool[_random.nextInt(_degreePool.length)];
    _triad = _diatonicTriad(_key, _degree);
    _target = romanNumeralOf(_triad.pitches, _key) ??
        RomanNumeral(_degree, _chordType(_triad.quality), 0);

    // Options: the answer plus distractors drawn from the other diatonic
    // degrees of this key (unique symbols), four buttons total.
    final pool = <String>{_target.symbol};
    final others = [..._allDegrees]..shuffle(_random);
    for (final d in others) {
      if (pool.length >= 4) break;
      pool.add(_symbolFor(_key, d));
    }
    _options = pool.toList()..shuffle(_random);

    _tapped = null;
    _lastAnswer = null;
  }

  void _playChord() => context
      .read<AudioService>()
      .playArpeggioThenChord(_triad.pitches.map((p) => p.midiNumber).toList());

  void _onAnswer(String symbol) {
    if (_lastAnswer == true) return; // round already won
    final correct = symbol == _target.symbol;

    // Record the first try per round (mirrors the other quizzes).
    if (_tapped == null || !answeredWrong) {
      context
          .read<SriService>()
          .recordResponse('harmony.roman.${_target.symbol}', correct);
    }

    final audio = context.read<AudioService>();
    if (correct) {
      audio.playMidiChord(_triad.pitches.map((p) => p.midiNumber).toList());
    } else {
      audio.playWrong();
    }

    setState(() {
      _tapped = symbol;
      _lastAnswer = correct;
    });
    final advanced = resolveAnswer(correct: correct);
    if (advanced && !finished) {
      // The next round's chord plays after the auto-advance delay.
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted && !finished) _playChord();
      });
    }
  }

  Score get _chordScore => Score(
        clef: Clef.treble,
        keySignature: _key.signature,
        measures: [
          Measure([
            NoteElement(
              pitches: _triad.pitches,
              duration: const NoteDuration(DurationBase.whole),
              id: 'chord',
            ),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final keyName = noteNameFor(context, _key.tonic.step);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameRomanNumeral)),
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
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.romanNumeralPrompt(keyName),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 32),
                                child: StaffView(
                                  score: _chordScore,
                                  staffSpace: 15,
                                  theme: kidsScoreTheme,
                                ),
                              ),
                              const SizedBox(height: 8),
                              IconButton.filledTonal(
                                onPressed: _playChord,
                                icon: const Icon(Icons.volume_up),
                                tooltip: l10n.romanNumeralReplay,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final symbol in _options)
                          SizedBox(
                            width: 96,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                backgroundColor: _tapped == null
                                    ? null
                                    : symbol == _target.symbol
                                        ? Colors.green
                                        : symbol == _tapped
                                            ? Colors.redAccent
                                            : null,
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              onPressed: () => _onAnswer(symbol),
                              child: Text(symbol),
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
