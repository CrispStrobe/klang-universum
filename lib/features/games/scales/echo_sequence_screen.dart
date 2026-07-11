// lib/features/games/scales/echo_sequence_screen.dart
//
// "Ton-Echo" — a melodic-memory game: four coloured pads each sound a pitch
// (a pentatonic set, so any sequence stays consonant). The app lights and
// plays a sequence that grows by one each round; the child echoes it back.
// One wrong pad ends the run; the score is the longest sequence reached.
// A memory-sequence toy mechanic reimagined for the ear.
//
// No SRI — this is pure short-term melodic memory, not a drilled fact.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/tuning.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

enum _Phase { watching, repeating, over }

class EchoSequenceScreen extends StatefulWidget {
  const EchoSequenceScreen({super.key});

  // Pentatonic pads (C D E G), so every sequence sounds musical.
  static const _midis = [60, 62, 64, 67];
  static const _colors = [
    Color(0xFFE53935), // red
    Color(0xFFFDD835), // yellow
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
  ];

  @override
  State<EchoSequenceScreen> createState() => _EchoSequenceScreenState();
}

class _EchoSequenceScreenState extends State<EchoSequenceScreen> {
  final _random = Random();
  final List<int> _sequence = [];
  _Phase _phase = _Phase.watching;
  int _watchPos = 0;
  int _inputIndex = 0;
  int _best = 0; // longest sequence completed
  int? _lit; // currently highlighted pad

  Timer? _watchTimer;
  Timer? _flashTimer;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _startTimer = Timer(const Duration(milliseconds: 600), _addAndWatch);
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _flashTimer?.cancel();
    _startTimer?.cancel();
    super.dispose();
  }

  void _addAndWatch() {
    if (!mounted) return;
    _sequence.add(_random.nextInt(EchoSequenceScreen._midis.length));
    _startWatch();
  }

  void _startWatch() {
    setState(() {
      _phase = _Phase.watching;
      _watchPos = 0;
      _inputIndex = 0;
      _lit = null;
    });
    _watchStep();
  }

  void _watchStep() {
    if (!mounted) return;
    if (_watchPos >= _sequence.length) {
      setState(() => _phase = _Phase.repeating);
      return;
    }
    final pad = _sequence[_watchPos];
    setState(() => _lit = pad);
    context.read<AudioService>().playMidiNote(EchoSequenceScreen._midis[pad]);
    _watchTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _lit = null);
      _watchTimer = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _watchPos++;
        _watchStep();
      });
    });
  }

  void _flash(int pad) {
    setState(() => _lit = pad);
    context.read<AudioService>().playMidiNote(
          EchoSequenceScreen._midis[pad],
          ms: 350,
        );
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _lit = null);
    });
  }

  void _onPad(int pad) {
    if (_phase != _Phase.repeating) return;
    _flash(pad);

    if (pad == _sequence[_inputIndex]) {
      _inputIndex++;
      if (_inputIndex == _sequence.length) {
        // Whole sequence echoed — grow it.
        _best = _sequence.length;
        setState(() => _phase = _Phase.watching);
        _startTimer = Timer(const Duration(milliseconds: 700), _addAndWatch);
      }
    } else {
      _gameOver();
    }
  }

  void _gameOver() {
    context.read<AudioService>().playWrong();
    context.read<ProgressService>().recordResult(
          'echo_sequence',
          score: _best * 100,
          stars: scoreToStars('echo_sequence', _best * 100, true),
        );
    setState(() => _phase = _Phase.over);
  }

  void _restart() {
    _watchTimer?.cancel();
    _flashTimer?.cancel();
    _startTimer?.cancel();
    _sequence.clear();
    _best = 0;
    _lit = null;
    setState(() => _phase = _Phase.watching);
    _startTimer = Timer(const Duration(milliseconds: 500), _addAndWatch);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameEchoSequence)),
      body: SafeArea(
        child: _phase == _Phase.over
            ? GameResultView(
                gameType: 'echo_sequence',
                score: _best * 100,
                onRestart: _restart,
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      _phase == _Phase.watching
                          ? l10n.echoWatch
                          : l10n.echoRepeat,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.echoLength(_sequence.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            children: [
                              for (var i = 0;
                                  i < EchoSequenceScreen._midis.length;
                                  i++)
                                _Pad(
                                  color: EchoSequenceScreen._colors[i],
                                  lit: _lit == i,
                                  onTap: _phase == _Phase.repeating
                                      ? () => _onPad(i)
                                      : null,
                                ),
                            ],
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

class _Pad extends StatelessWidget {
  final Color color;
  final bool lit;
  final VoidCallback? onTap;

  const _Pad({required this.color, required this.lit, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: lit ? color : color.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: lit ? Colors.white : Colors.black26,
            width: lit ? 4 : 2,
          ),
          boxShadow: lit
              ? [BoxShadow(color: color, blurRadius: 24, spreadRadius: 2)]
              : null,
        ),
      ),
    );
  }
}
