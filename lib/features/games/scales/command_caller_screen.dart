// lib/features/games/scales/command_caller_screen.dart
//
// "Der Dirigent" / "Follow the Conductor" — the command-caller toy mechanic
// (docs/PLAN.md toy-inspired list) given a musical frame: the conductor calls a
// gesture (tap, hold, or a swipe), and the child must perform it before the
// countdown bar empties. Each correct cue sounds the next note of a rising
// pentatonic melody, so a good run plays a little tune; misses cost a heart.
// Reaction + gesture vocabulary, with a musical payoff. A pure toy — no SRI,
// scored like Sound Echo.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/tuning.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/note_mascot.dart';
import 'package:provider/provider.dart';

/// A conductor cue. [key] is stable (used by tests + as a switch tag).
enum Command {
  tap('tap', Icons.touch_app),
  hold('hold', Icons.back_hand),
  swipeLeft('swipeLeft', Icons.west),
  swipeRight('swipeRight', Icons.east),
  swipeUp('swipeUp', Icons.north),
  swipeDown('swipeDown', Icons.south);

  const Command(this.key, this.icon);

  final String key;
  final IconData icon;
}

class CommandCallerScreen extends StatefulWidget {
  const CommandCallerScreen({super.key});

  /// Cues per run — the round budget behind the star rating.
  static const _kTotalRounds = 15;
  static const _kMaxLives = 3;

  @visibleForTesting
  static const maxLives = _kMaxLives;

  /// Key on the gesture pad, so tests can drive it.
  @visibleForTesting
  static const padKey = ValueKey('conductor_pad');

  // Rising C-major pentatonic — every correct cue plays the next note.
  static const _melody = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81];

  @override
  State<CommandCallerScreen> createState() => _CommandCallerScreenState();
}

/// Typed window into the game for widget tests (the state class is private).
@visibleForTesting
abstract interface class CommandCallerTester {
  int get score;
  int get lives;
  bool get finished;

  /// Stable key of the cue currently called, or null between/after rounds.
  String? get currentCommandKey;
}

class _CommandCallerScreenState extends State<CommandCallerScreen>
    with SingleTickerProviderStateMixin
    implements CommandCallerTester {
  final _random = Random();

  // The countdown bar doubles as the round timer: when it completes, the cue
  // timed out. One source of truth for both the visual and the deadline.
  late final AnimationController _clock = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _resolve(null);
    });

  Command? _target;
  int _round = 0;
  int _score = 0;
  int _combo = 0;
  int _lives = CommandCallerScreen._kMaxLives;
  int _correct = 0;
  bool _finished = false;
  bool _answered = false; // guard: one resolution per round
  bool? _lastOk;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  Offset _dragStart = Offset.zero;

  int get _level => 1 + _correct ~/ 4;
  int get _multiplier => (1 + _combo ~/ 3).clamp(1, 5);
  int get _windowMs => (2600 - 300 * (_level - 1)).clamp(1200, 2600);

  @override
  int get score => _score;
  @override
  int get lives => _lives;
  @override
  bool get finished => _finished;
  @override
  String? get currentCommandKey => _answered ? null : _target?.key;

  // Level 1 keeps to tap/hold/left/right; up & down join at level 2.
  List<Command> get _pool => _level >= 2
      ? Command.values
      : const [
          Command.tap,
          Command.hold,
          Command.swipeLeft,
          Command.swipeRight,
        ];

  @override
  void initState() {
    super.initState();
    _nextRound();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _nextRound() {
    // Callers rebuild (initState builds next; the advance path setStates
    // `_round`), so plain assignment is enough — and safe to call from
    // initState.
    final pool = _pool;
    _target = pool[_random.nextInt(pool.length)];
    _answered = false;
    _lastOk = null;
    _mascot = NoteMascotMood.idle;
    context.read<AudioService>().playMidiNote(72, ms: 90); // a short call cue
    _clock
      ..duration = Duration(milliseconds: _windowMs)
      ..forward(from: 0);
  }

  void _perform(Command gesture) {
    if (_finished || _answered || _target == null) return;
    _resolve(gesture);
  }

  void _resolve(Command? gesture) {
    if (_answered || _finished) return;
    _answered = true;
    _clock.stop();
    final ok = gesture == _target;
    final audio = context.read<AudioService>();

    if (ok) {
      _correct++;
      _combo++;
      _score += 10 * _multiplier;
      audio.playMidiNote(
        CommandCallerScreen
            ._melody[(_correct - 1) % CommandCallerScreen._melody.length],
        ms: 320,
      );
    } else {
      _lives--;
      _combo = 0;
      audio.playWrong();
    }

    setState(() {
      _lastOk = ok;
      _mascot = ok ? NoteMascotMood.happy : NoteMascotMood.oops;
    });

    final done = _lives <= 0 || _round + 1 >= CommandCallerScreen._kTotalRounds;
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (done) {
        _finish();
      } else {
        setState(() => _round++);
        _nextRound();
      }
    });
  }

  void _finish() {
    _clock.stop();
    context.read<AudioService>().playFanfare();
    context.read<ProgressService>().recordResult(
          'command_caller',
          score: _score,
          stars: scoreToStars('command_caller', _score, true),
        );
    setState(() => _finished = true);
  }

  void _restart() {
    setState(() {
      _round = 0;
      _score = 0;
      _combo = 0;
      _lives = CommandCallerScreen._kMaxLives;
      _correct = 0;
      _finished = false;
    });
    _nextRound();
  }

  // --- Gesture reading -------------------------------------------------------

  void _onPanEnd(DragEndDetails d, Offset end) {
    final delta = end - _dragStart;
    if (delta.distance < 30) return; // too small to be a swipe
    final Command dir;
    if (delta.dx.abs() > delta.dy.abs()) {
      dir = delta.dx < 0 ? Command.swipeLeft : Command.swipeRight;
    } else {
      dir = delta.dy < 0 ? Command.swipeUp : Command.swipeDown;
    }
    _perform(dir);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameCommandCaller)),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'command_caller',
                score: _score,
                onRestart: _restart,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _Hud(
                      round: _round + 1,
                      totalRounds: CommandCallerScreen._kTotalRounds,
                      score: _score,
                      multiplier: _multiplier,
                      lives: _lives,
                      maxLives: CommandCallerScreen._kMaxLives,
                      mascot: _mascot,
                    ),
                    const SizedBox(height: 8),
                    // The shrinking countdown bar.
                    AnimatedBuilder(
                      animation: _clock,
                      builder: (context, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: 1 - _clock.value,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: GestureDetector(
                        key: CommandCallerScreen.padKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _perform(Command.tap),
                        onLongPress: () => _perform(Command.hold),
                        onPanStart: (d) => _dragStart = d.localPosition,
                        onPanEnd: (d) => _onPanEnd(d, d.localPosition),
                        child: _CommandPad(
                          command: _target,
                          lastOk: _lastOk,
                          label: _target == null
                              ? ''
                              : _commandLabel(l10n, _target!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.commandCallerHint,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  String _commandLabel(AppLocalizations l10n, Command c) => switch (c) {
        Command.tap => l10n.commandTap,
        Command.hold => l10n.commandHold,
        Command.swipeLeft => l10n.commandSwipeLeft,
        Command.swipeRight => l10n.commandSwipeRight,
        Command.swipeUp => l10n.commandSwipeUp,
        Command.swipeDown => l10n.commandSwipeDown,
      };
}

class _CommandPad extends StatelessWidget {
  const _CommandPad({
    required this.command,
    required this.lastOk,
    required this.label,
  });

  final Command? command;
  final bool? lastOk;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = lastOk == null
        ? scheme.primaryContainer
        : lastOk!
            ? Colors.green.shade100
            : Colors.red.shade100;
    final fg = lastOk == null
        ? scheme.onPrimaryContainer
        : lastOk!
            ? Colors.green.shade800
            : Colors.red.shade800;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(command?.icon ?? Icons.music_note, size: 96, color: fg),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.round,
    required this.totalRounds,
    required this.score,
    required this.multiplier,
    required this.lives,
    required this.maxLives,
    required this.mascot,
  });

  final int round;
  final int totalRounds;
  final int score;
  final int multiplier;
  final int lives;
  final int maxLives;
  final NoteMascotMood mascot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        NoteMascot(mood: mascot, size: 30),
        const SizedBox(width: 8),
        const Icon(Icons.star, color: Colors.amber, size: 22),
        const SizedBox(width: 4),
        Text(
          '$score',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Text(
          l10n.roundOf(round, totalRounds),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const Spacer(),
        if (multiplier > 1) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              l10n.fallingMultiplier(multiplier),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        for (var i = 0; i < maxLives; i++)
          Icon(
            i < lives ? Icons.favorite : Icons.favorite_border,
            color: i < lives ? Colors.redAccent : scheme.outlineVariant,
            size: 22,
          ),
      ],
    );
  }
}
