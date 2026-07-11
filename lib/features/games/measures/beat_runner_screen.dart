// lib/features/games/measures/beat_runner_screen.dart
//
// "Im Takt" / "Beat Runner" — the tap-along rhythm lane (docs/PLAN.md
// opportunity backlog: "play-in-time-to-music lane"). Markers fall down a lane
// and cross a glowing hit-line exactly on each beat; the child taps in time.
// The game's own Ticker is the master clock, so the groove (a bass note per
// beat), the falling markers, and the tap timing all reference one clock — no
// audio-latency drift. Taps score Perfect / Good by accuracy; a no-fail toy
// (every run finishes), scored like Sound Echo.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/tuning.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/note_mascot.dart';
import 'package:provider/provider.dart';

class BeatRunnerScreen extends StatefulWidget {
  const BeatRunnerScreen({super.key});

  static const _kBeats = 16;
  static const _kBeatMs = 650; // ~92 BPM
  static const _kTravelMs = 1300; // a marker is airborne for two beats
  static const _kLeadMs = _kTravelMs + 700; // time of beat 0
  static const _kHitWindowMs = 180; // a tap this close counts
  static const _kPerfectMs = 75; // …this close is Perfect

  /// A steady two-bar bass groove (C–G–F–G), one note per beat.
  static const _kBass = [48, 48, 55, 55, 53, 53, 55, 55];

  /// Bright notes played on a good hit — a rising pentatonic sparkle.
  static const _kSparkle = [72, 74, 76, 79, 81, 84];

  @visibleForTesting
  static const padKey = ValueKey('beat_pad');

  /// Ticker time (ms) at which beat [k] lands on the hit-line.
  static int beatTimeMs(int k) => _kLeadMs + k * _kBeatMs;

  @override
  State<BeatRunnerScreen> createState() => _BeatRunnerScreenState();
}

/// Typed window into the game for widget tests (the state class is private).
@visibleForTesting
abstract interface class BeatRunnerTester {
  int get score;
  int get hits;
  bool get finished;
  int get nowMs;
}

enum _Judgement { perfect, good, miss }

class _BeatRunnerScreenState extends State<BeatRunnerScreen>
    with SingleTickerProviderStateMixin
    implements BeatRunnerTester {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<int> _now = ValueNotifier<int>(0);

  final List<bool> _resolved =
      List<bool>.filled(BeatRunnerScreen._kBeats, false);

  int _score = 0;
  int _hits = 0;
  int _combo = 0;
  int _lastBeatPlayed = -1;
  bool _finished = false;

  _Judgement? _lastJudgement;
  int _judgementUntil = 0;
  NoteMascotMood _mascot = NoteMascotMood.idle;

  @override
  int get score => _score;
  @override
  int get hits => _hits;
  @override
  bool get finished => _finished;
  @override
  int get nowMs => _now.value;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  double _progress(int k, int now) {
    final land = BeatRunnerScreen.beatTimeMs(k);
    return (now - (land - BeatRunnerScreen._kTravelMs)) /
        BeatRunnerScreen._kTravelMs;
  }

  void _onTick(Duration elapsed) {
    if (_finished) return;
    final now = elapsed.inMilliseconds;

    // Play the groove: one bass note as each beat lands.
    while (_lastBeatPlayed + 1 < BeatRunnerScreen._kBeats &&
        now >= BeatRunnerScreen.beatTimeMs(_lastBeatPlayed + 1)) {
      _lastBeatPlayed++;
      context.read<AudioService>().playMidiNote(
            BeatRunnerScreen
                ._kBass[_lastBeatPlayed % BeatRunnerScreen._kBass.length],
            ms: 240,
          );
    }

    // Retire beats whose window has closed uncaught → a miss.
    var missed = false;
    for (var k = 0; k < BeatRunnerScreen._kBeats; k++) {
      if (!_resolved[k] &&
          now >
              BeatRunnerScreen.beatTimeMs(k) + BeatRunnerScreen._kHitWindowMs) {
        _resolved[k] = true;
        _combo = 0;
        _lastJudgement = _Judgement.miss;
        _judgementUntil = now + 350;
        _mascot = NoteMascotMood.oops;
        missed = true;
      }
    }

    _now.value = now;
    if (missed) setState(() {});

    if (now >
        BeatRunnerScreen.beatTimeMs(BeatRunnerScreen._kBeats - 1) +
            BeatRunnerScreen._kHitWindowMs +
            400) {
      _finish();
    }
  }

  int get _multiplier => (1 + _combo ~/ 4).clamp(1, 4);

  void _onTap() {
    if (_finished) return;
    final now = _now.value;

    // Nearest unresolved beat within the hit window.
    var best = -1;
    var bestDelta = BeatRunnerScreen._kHitWindowMs + 1;
    for (var k = 0; k < BeatRunnerScreen._kBeats; k++) {
      if (_resolved[k]) continue;
      final d = (now - BeatRunnerScreen.beatTimeMs(k)).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = k;
      }
    }
    if (best < 0) return; // off-beat tap — no marker to catch, no penalty

    _resolved[best] = true;
    _hits++;
    _combo++;
    final perfect = bestDelta <= BeatRunnerScreen._kPerfectMs;
    _score += (perfect ? 20 : 10) * _multiplier;
    _lastJudgement = perfect ? _Judgement.perfect : _Judgement.good;
    _judgementUntil = now + 350;
    _mascot = NoteMascotMood.happy;
    context.read<AudioService>().playMidiNote(
          BeatRunnerScreen
              ._kSparkle[(_hits - 1) % BeatRunnerScreen._kSparkle.length],
          ms: 260,
        );
    setState(() {});
  }

  void _finish() {
    _finished = true;
    _ticker.stop();
    context.read<AudioService>().playFanfare();
    context.read<ProgressService>().recordResult(
          'beat_runner',
          score: _score,
          stars: scoreToStars('beat_runner', _score, true),
        );
    setState(() {});
  }

  void _restart() {
    _ticker.stop();
    for (var k = 0; k < _resolved.length; k++) {
      _resolved[k] = false;
    }
    _score = 0;
    _hits = 0;
    _combo = 0;
    _lastBeatPlayed = -1;
    _lastJudgement = null;
    _finished = false;
    _mascot = NoteMascotMood.idle;
    _now.value = 0;
    setState(() {});
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameBeatRunner)),
      body: SafeArea(
        child: _finished
            ? GameResultView(
                gameType: 'beat_runner',
                score: _score,
                onRestart: _restart,
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Row(
                      children: [
                        NoteMascot(mood: _mascot, size: 30),
                        const SizedBox(width: 8),
                        const Icon(Icons.star, color: Colors.amber, size: 22),
                        const SizedBox(width: 4),
                        Text(
                          '$_score',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          l10n.beatRunnerHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      key: BeatRunnerScreen.padKey,
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => _onTap(),
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            ValueListenableBuilder<int>(
                          valueListenable: _now,
                          builder: (context, now, _) => CustomPaint(
                            size: constraints.biggest,
                            painter: _BeatPainter(
                              now: now,
                              progress: _progress,
                              resolved: _resolved,
                              beats: BeatRunnerScreen._kBeats,
                              judgement:
                                  now < _judgementUntil ? _lastJudgement : null,
                              scheme: Theme.of(context).colorScheme,
                              perfectLabel: l10n.beatPerfect,
                              goodLabel: l10n.beatGood,
                              missLabel: l10n.beatMiss,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BeatPainter extends CustomPainter {
  _BeatPainter({
    required this.now,
    required this.progress,
    required this.resolved,
    required this.beats,
    required this.judgement,
    required this.scheme,
    required this.perfectLabel,
    required this.goodLabel,
    required this.missLabel,
  });

  final int now;
  final double Function(int, int) progress;
  final List<bool> resolved;
  final int beats;
  final _Judgement? judgement;
  final ColorScheme scheme;
  final String perfectLabel;
  final String goodLabel;
  final String missLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final hitY = size.height * 0.82;
    final cx = size.width / 2;

    // The hit-line + a target ring.
    canvas.drawLine(
      Offset(0, hitY),
      Offset(size.width, hitY),
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      Offset(cx, hitY),
      30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = scheme.primary.withValues(alpha: 0.6),
    );

    // Falling markers.
    for (var k = 0; k < beats; k++) {
      final p = progress(k, now);
      if (p < 0 || p > 1.25) continue;
      // Caught/missed markers stop drawing once past the line.
      if (resolved[k] && p > 1.0) continue;
      final y = p * hitY;
      final caughtGlow = resolved[k];
      canvas.drawCircle(
        Offset(cx, y),
        caughtGlow ? 26 : 20,
        Paint()
          ..color = (caughtGlow ? Colors.green : scheme.tertiary)
              .withValues(alpha: caughtGlow ? 0.4 : 1.0),
      );
    }

    // Judgement text.
    if (judgement != null) {
      final (text, color) = switch (judgement!) {
        _Judgement.perfect => (perfectLabel, Colors.amber),
        _Judgement.good => (goodLabel, Colors.lightGreen),
        _Judgement.miss => (missLabel, Colors.redAccent),
      };
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, hitY - 90));
    }
  }

  @override
  bool shouldRepaint(covariant _BeatPainter old) => true;
}
