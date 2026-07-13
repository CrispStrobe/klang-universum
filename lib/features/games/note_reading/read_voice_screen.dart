// lib/features/games/note_reading/read_voice_screen.dart
//
// "Read the Voice" — reading an individual line out of a multi-voice texture, on
// partitura's `Measure.voice2` (two voices per staff, stems up/down). A chord is
// shown with one voice highlighted; the child names the note THAT voice sings —
// so they must track the right line, not just any note. The 4-voice generalisation
// of Duet (which highlights one part of a two-staff system).
//
// Difficulty grows 2 voices (Soprano + Alto, one treble staff) → full SATB (four
// voices across a grand staff). C major only for now. Gated behind Duet.
//
// SRI: 'note_reading.<clef>.<step><octave>' on the highlighted note (shared pool).

import 'dart:math';

// Material also exports `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:klang_universum/shared/score_theme.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

const _whole = NoteDuration(DurationBase.whole);

enum _Voice { soprano, alto, tenor, bass }

/// One voice in the current chord: its pitch, staff/stem role and element id.
class _Part {
  final _Voice voice;
  final Pitch pitch;
  final String id; // 's' | 'a' | 't' | 'b'
  const _Part(this.voice, this.pitch, this.id);
}

class ReadVoiceScreen extends StatefulWidget {
  const ReadVoiceScreen({super.key});

  @override
  State<ReadVoiceScreen> createState() => _ReadVoiceScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class ReadVoiceTester {
  /// Letter of the highlighted voice's note (the correct answer).
  Step get answerStep;
  bool get isFinished;
}

class _ReadVoiceScreenState extends State<ReadVoiceScreen>
    with QuizRoundMixin
    implements ReadVoiceTester {
  final _random = Random();

  // Major-key diatonic triads by degree (C major): (root Step, quality).
  static const _degrees = <(Step, ChordQuality)>[
    (Step.c, ChordQuality.major), // I
    (Step.f, ChordQuality.major), // IV
    (Step.g, ChordQuality.major), // V
    (Step.d, ChordQuality.minor), // ii
    (Step.e, ChordQuality.minor), // iii
    (Step.a, ChordQuality.minor), // vi
    (Step.b, ChordQuality.diminished), // vii°
  ];

  int _stars = 0;
  late List<_Part> _parts; // active voices this round
  late _Part _target;
  late List<Step> _options;
  Step? _tapped;
  bool? _lastAnswer;

  bool get _satb => _stars >= 1; // 4 voices once past level 0

  @override
  Step get answerStep => _target.pitch.step;
  @override
  bool get isFinished => finished;

  @override
  int get totalRounds => 10;
  @override
  bool get playFeedbackSounds => false;
  @override
  String get gameType => 'read_voice';

  @override
  void initState() {
    super.initState();
    _stars = context.read<ProgressService>().starsFor(gameType);
    prepareRound();
  }

  /// The smallest MIDI >= [floor] whose pitch class is one of [pcs].
  int _nextTone(int floor, Set<int> pcs) {
    var m = floor;
    while (!pcs.contains(m % 12)) {
      m++;
    }
    return m;
  }

  @override
  void prepareRound() {
    final (root, quality) = _degrees[_random.nextInt(_satb ? 7 : 3)];
    final pcs = Triad(Pitch(root), quality)
        .pitches
        .map((p) => p.midiNumber % 12)
        .toSet();

    // Bass in octave 3; each upper voice the next chord tone above, with the
    // alto pushed to middle C so Soprano/Alto sit on the treble staff and
    // Tenor/Bass on the bass staff — no voice crossing.
    final rootPc = Pitch(root).midiNumber % 12;
    final bass = 48 + rootPc;
    final tenor = _nextTone(bass + 3, pcs);
    final alto = _nextTone(max(60, tenor + 1), pcs);
    final soprano = _nextTone(alto + 3, pcs);

    _parts = [
      _Part(_Voice.soprano, pitchFromMidi(soprano), 's'),
      _Part(_Voice.alto, pitchFromMidi(alto), 'a'),
      if (_satb) _Part(_Voice.tenor, pitchFromMidi(tenor), 't'),
      if (_satb) _Part(_Voice.bass, pitchFromMidi(bass), 'b'),
    ];
    _target = _parts[_random.nextInt(_parts.length)];

    final distractors = [...Step.values]
      ..remove(_target.pitch.step)
      ..shuffle(_random);
    _options = [_target.pitch.step, ...distractors.take(3)]..shuffle(_random);
    _tapped = null;
    _lastAnswer = null;
  }

  _Part? _part(_Voice v) {
    for (final p in _parts) {
      if (p.voice == v) return p;
    }
    return null;
  }

  /// One staff (voice1 = upper part stems up, voice2 = lower part stems down).
  Score _staff(Clef clef, _Part upper, _Part? lower) => Score(
        clef: clef,
        measures: [
          Measure(
            [NoteElement.note(upper.pitch, _whole, id: upper.id)],
            voice2: lower == null
                ? const []
                : [NoteElement.note(lower.pitch, _whole, id: lower.id)],
          ),
        ],
      );

  StaffSystem get _system => StaffSystem([
        _staff(Clef.treble, _part(_Voice.soprano)!, _part(_Voice.alto)),
        if (_satb) _staff(Clef.bass, _part(_Voice.tenor)!, _part(_Voice.bass)),
      ]);

  String _voiceName(AppLocalizations l, _Voice v) => switch (v) {
        _Voice.soprano => l.voiceSoprano,
        _Voice.alto => l.voiceAlto,
        _Voice.tenor => l.voiceTenor,
        _Voice.bass => l.voiceBass,
      };

  Clef get _targetClef =>
      _target.voice == _Voice.tenor || _target.voice == _Voice.bass
          ? Clef.bass
          : Clef.treble;

  String get _sriId =>
      'note_reading.${_targetClef.name}.${_target.pitch.step.name}'
      '${_target.pitch.octave}';

  void _hearVoice() =>
      context.read<AudioService>().playMidiNote(_target.pitch.midiNumber);

  void _onAnswer(Step choice) {
    if (_lastAnswer == true) return;
    final correct = choice == _target.pitch.step;
    if (_tapped == null || !answeredWrong) {
      context.read<SriService>().recordResponse(_sriId, correct);
    }
    if (correct) {
      _hearVoice();
    } else {
      context.read<AudioService>().playWrong();
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
      appBar: AppBar(title: Text(l10n.gameReadVoice)),
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
                      prompt: l10n.readVoicePrompt(
                        _voiceName(l10n, _target.voice),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Card(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                child: StaffSystemView(
                                  system: _system,
                                  staffSpace: 13,
                                  theme: kidsScoreTheme,
                                  highlightedIds: {_target.id},
                                ),
                              ),
                              IconButton.filledTonal(
                                onPressed: _hearVoice,
                                icon: const Icon(Icons.volume_up),
                                tooltip: l10n.readVoiceHear,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FeedbackLine(correct: _lastAnswer),
                    const SizedBox(height: 12),
                    AnswerGrid(
                      children: [
                        for (final option in _options)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _tapped == null
                                  ? null
                                  : option == _target.pitch.step
                                      ? Colors.green
                                      : option == _tapped
                                          ? Colors.redAccent
                                          : null,
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _onAnswer(option),
                            child: Text(noteNameFor(context, option)),
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
