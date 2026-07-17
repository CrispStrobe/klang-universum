// lib/features/games/note_reading/spacing_read_screen.dart
//
// "Close or Open?" — read an SATB four-part chord on the grand staff and tap
// whether the upper three voices are in CLOSE or OPEN position. The textbook
// rule: close position keeps Soprano and Tenor within one octave (the upper
// voices take consecutive chord tones); open position spreads them more than an
// octave apart (each adjacent upper voice skips a chord tone). A fresh
// voice-leading skill — not another note-namer. Reuses the SATB
// voicing/rendering scaffold (`satb_voicing.dart`).
//
// Difficulty: 1★ C major primary triads (I/IV/V), root position; 2★ several
// major keys + all seven diatonic triads.
//
// SRI: 'note_reading.spacing.<close|open>'.

import 'dart:math';

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/progress_service.dart';
import 'package:comet_beat/core/services/sri_service.dart';
import 'package:comet_beat/features/games/note_reading/satb_voicing.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/features/games/widgets/game_widgets.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
// Material also exports `Step` (Stepper) and `Interval` (animation); crisp_notation's win here.
import 'package:flutter/material.dart' hide Interval, Step;
import 'package:provider/provider.dart';

// Major-key diatonic triads by scale degree: (interval above the tonic,
// quality). null = the tonic. The first three are the primary triads (I/IV/V),
// used below 2★.
const _degrees = <(Interval?, ChordQuality)>[
  (null, ChordQuality.major), // I
  (Interval.perfectFourth, ChordQuality.major), // IV
  (Interval.perfectFifth, ChordQuality.major), // V
  (Interval.majorSecond, ChordQuality.minor), // ii
  (Interval.majorThird, ChordQuality.minor), // iii
  (Interval.majorSixth, ChordQuality.minor), // vi
  (Interval.majorSeventh, ChordQuality.diminished), // vii°
];

const _wideKeys = [
  Pitch(Step.c),
  Pitch(Step.g),
  Pitch(Step.f),
  Pitch(Step.d),
  Pitch(Step.b, alter: -1), // B♭
];

/// The smallest midi ≥ [floor] whose pitch class is a chord tone.
int _nextTone(int floor, Set<int> pcs) {
  var m = floor;
  while (!pcs.contains(m % 12)) {
    m++;
  }
  return m;
}

/// The [n]-th chord tone strictly above [m] (n=1 → the next tone; n=2 → skip
/// one, etc.).
int _toneAbove(int m, int n, Set<int> pcs) {
  var cur = m;
  for (var i = 0; i < n; i++) {
    cur = _nextTone(cur + 1, pcs);
  }
  return cur;
}

/// A voiced SATB chord plus whether its upper voices are open-position.
class SpacingChord {
  final List<SatbPart> parts;
  final bool open;
  const SpacingChord(this.parts, this.open);

  /// The four pitches, low → high, for playback.
  List<int> get midis =>
      (parts.map((p) => p.pitch.midiNumber).toList()..sort());
}

/// Voice a random diatonic triad into SATB, either close or open. The bass is
/// the root low on the bass staff; the three upper voices stack as chord tones —
/// consecutive tones (close) or skipping every other tone (open) — so the
/// soprano-tenor span lands ≤ an octave (close) or > an octave (open).
SpacingChord voiceSpacing(
  Random random, {
  required bool open,
  required bool wide,
}) {
  final keys = wide ? _wideKeys : const [Pitch(Step.c)];
  final tonic = keys[random.nextInt(keys.length)];
  final (interval, quality) = _degrees[random.nextInt(wide ? 7 : 3)];
  final root = interval == null ? tonic : tonic.transposeBy(interval);

  // pitch class → correctly-spelled chord tone (so accidentals draw right).
  final spelled = {
    for (final p in Triad(root, quality).pitches) p.midiNumber % 12: p,
  };
  final pcs = spelled.keys.toSet();
  Pitch at(int midi) {
    final p = spelled[midi % 12]!;
    return Pitch(p.step, alter: p.alter, octave: midi ~/ 12 - 1);
  }

  // Bass: the root low on the bass staff (keep it below ~E3 so the upper
  // structure has room without crowding).
  var bass = 48 + root.midiNumber % 12;
  if (bass > 52) bass -= 12; // F..B → octave 2, so bass ∈ [F2..E3]
  // Tenor: a chord tone a third-or-so above the bass (top of the bass staff).
  final tenor = _nextTone(bass + 4, pcs);
  final gap = open ? 2 : 1;
  final alto = _toneAbove(tenor, gap, pcs);
  final soprano = _toneAbove(alto, gap, pcs);

  return SpacingChord(
    [
      SatbPart(SatbVoice.soprano, at(soprano)),
      SatbPart(SatbVoice.alto, at(alto)),
      SatbPart(SatbVoice.tenor, at(tenor)),
      SatbPart(SatbVoice.bass, at(bass)),
    ],
    open,
  );
}

class SpacingReadScreen extends StatefulWidget {
  const SpacingReadScreen({super.key});

  @override
  State<SpacingReadScreen> createState() => _SpacingReadScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class SpacingReadTester {
  /// Whether the current chord is open position (the correct answer).
  bool get isOpen;
  bool get isFinished;
}

class _SpacingReadScreenState extends State<SpacingReadScreen>
    with QuizRoundMixin
    implements SpacingReadTester {
  final _random = Random();

  int _stars = 0;
  late SpacingChord _chord;
  bool? _tappedOpen;
  bool? _lastAnswer;

  @override
  bool get isOpen => _chord.open;
  @override
  bool get isFinished => finished;

  @override
  int get totalRounds => 10;
  @override
  bool get playFeedbackSounds => false;
  @override
  String get gameType => 'spacing_read';

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
  }

  @override
  void prepareRound() {
    _chord = voiceSpacing(
      _random,
      open: _random.nextBool(),
      wide: _stars >= 2,
    );
    _tappedOpen = null;
    _lastAnswer = null;
  }

  void _hearChord() => context.read<AudioService>().playMidiChord(_chord.midis);

  void _onAnswer(bool choseOpen) {
    if (_lastAnswer == true) return;
    final correct = choseOpen == _chord.open;
    if (_tappedOpen == null || !answeredWrong) {
      context.read<SriService>().recordResponse(
            'note_reading.spacing.${_chord.open ? 'open' : 'close'}',
            correct,
          );
    }
    if (correct) {
      _hearChord();
    } else {
      context.read<AudioService>().playWrong();
    }
    setState(() {
      _tappedOpen = choseOpen;
      _lastAnswer = correct;
    });
    resolveAnswer(correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameSpacingRead),
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
                      prompt: l10n.spacingReadPrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Card(
                        // The Card fills the available (Expanded) height; the
                        // staff scales into whatever is left above the button, so
                        // open voicings (a taller grand staff) never overflow and
                        // the notation still grows on taller screens.
                        child: Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                child: FittedBox(
                                  child: StaffSystemView(
                                    system: satbSystem(_chord.parts),
                                    staffSpace: 13,
                                    theme: kidsScoreTheme,
                                  ),
                                ),
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: _hearChord,
                              icon: const Icon(Icons.volume_up),
                              tooltip: l10n.readVoiceHear,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        _spacingButton(context, l10n.spacingClose, open: false),
                        _spacingButton(context, l10n.spacingOpen, open: true),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _spacingButton(
    BuildContext context,
    String label, {
    required bool open,
  }) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _tappedOpen == null
            ? null
            : open == _chord.open
                ? Colors.green
                : open == _tappedOpen
                    ? Colors.redAccent
                    : null,
        textStyle: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      onPressed: () => _onAnswer(open),
      child: Text(label),
    );
  }
}
