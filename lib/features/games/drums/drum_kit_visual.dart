// A GarageBand-style VISUAL drum kit that lights up as it plays. A drawn kit
// (cymbals · toms · snare · kick · hi-hat · accents) whose pieces flash and
// glow the instant their [Drum] sounds — driven by the step sequencer during
// playback/recording, and by [DrumKitVisualController.flash] on a live pad tap.
//
// Self-contained: its own decay [Ticker] + [CustomPainter], no audio. Reads a
// `step` ValueListenable + a `hitAt(drum, step)` query (so it needs nothing of
// the screen's internals) and an optional controller for live hits.
//
// Flutter-only → widget-tested in test/drum_kit_visual_test.dart.

import 'dart:math';

import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Fires a one-shot flash for a [Drum] — used for LIVE feedback (a pad tap, a
/// classified beatbox hit) that doesn't come from the step clock.
class DrumKitVisualController extends ChangeNotifier {
  Drum? _last;
  int _seq = 0;

  Drum? get lastFlash => _last;

  /// The flash counter — bumped on every [flash] so repeated hits of the SAME
  /// drum still register (a plain value-equality listener would miss them).
  int get seq => _seq;

  void flash(Drum drum) {
    _last = drum;
    _seq++;
    notifyListeners();
  }
}

/// Test handle onto a running [DrumKitVisual] (the state class is private).
@visibleForTesting
abstract interface class DrumKitVisualTester {
  /// The current glow (0 = dark … 1 = just struck) of [drum].
  double glowOf(Drum drum);
}

/// The visual kit. [step] is the sequencer playhead (−1 = stopped); on each
/// advance, every drum with `hitAt(drum, step) == true` flashes. [drums] limits
/// which voices are drawn (defaults to the full kit).
class DrumKitVisual extends StatefulWidget {
  const DrumKitVisual({
    super.key,
    required this.step,
    required this.hitAt,
    this.controller,
    this.drums = Drum.values,
  });

  final ValueListenable<int> step;
  final bool Function(Drum drum, int step) hitAt;
  final DrumKitVisualController? controller;
  final List<Drum> drums;

  @override
  State<DrumKitVisual> createState() => _DrumKitVisualState();
}

class _DrumKitVisualState extends State<DrumKitVisual>
    with SingleTickerProviderStateMixin
    implements DrumKitVisualTester {
  // Per-drum glow intensity (0 = dark, 1 = just struck), decayed each frame.
  final Map<Drum, double> _glow = {for (final d in Drum.values) d: 0.0};
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _lastStep = -1;
  int _lastFlashSeq = 0;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    widget.step.addListener(_onStep);
    widget.controller?.addListener(_onFlash);
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void didUpdateWidget(DrumKitVisual old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) {
      old.step.removeListener(_onStep);
      widget.step.addListener(_onStep);
    }
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onFlash);
      widget.controller?.addListener(_onFlash);
    }
  }

  @override
  void dispose() {
    widget.step.removeListener(_onStep);
    widget.controller?.removeListener(_onFlash);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  double glowOf(Drum drum) => _glow[drum] ?? 0.0;

  void _light(Drum drum) {
    _glow[drum] = 1.0;
    _active = true;
  }

  void _onStep() {
    final s = widget.step.value;
    if (s == _lastStep) return;
    _lastStep = s;
    if (s < 0) return;
    for (final d in widget.drums) {
      if (widget.hitAt(d, s)) _light(d);
    }
  }

  void _onFlash() {
    final c = widget.controller;
    if (c == null || c.seq == _lastFlashSeq) return;
    _lastFlashSeq = c.seq;
    final d = c.lastFlash;
    if (d != null) _light(d);
  }

  void _onFrame(Duration now) {
    if (!_active) {
      _lastTick = now;
      return;
    }
    final dt = (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    // Exponential decay: a struck piece flares then fades over ~0.4 s.
    final k = exp(-dt * 6.0);
    var anyLit = false;
    for (final d in _glow.keys) {
      final g = _glow[d]! * k;
      _glow[d] = g < 1e-3 ? 0.0 : g;
      if (_glow[d]! > 0) anyLit = true;
    }
    _active = anyLit;
    _repaint.value++; // drive the CustomPainter without a full rebuild
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DrumKitPainter(
          glow: _glow,
          drums: widget.drums,
          dark: dark,
          repaint: _repaint,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ── Layout ───────────────────────────────────────────────────────────────────

enum _Shape { cymbal, hihat, tom, kick, snare, puck }

/// One drawn piece: where it sits (normalized 0..1), how big (fraction of the
/// canvas' shorter side), its base hue, and how to draw it.
class _Piece {
  const _Piece(this.drum, this.shape, this.cx, this.cy, this.r, this.color);
  final Drum drum;
  final _Shape shape;
  final double cx, cy, r;
  final Color color;
}

// A right-facing kit seen from the drummer's front. Back-to-front paint order.
const _kBrass = Color(0xFFC9A227);
const _kTom = Color(0xFF7E4A2B);
const _kShell = Color(0xFF2E3440);

const List<_Piece> _kLayout = [
  // Cymbals + hi-hat sit high, behind the drums.
  _Piece(Drum.crash, _Shape.cymbal, 0.21, 0.26, 0.15, _kBrass),
  _Piece(Drum.ride, _Shape.cymbal, 0.82, 0.24, 0.17, _kBrass),
  _Piece(Drum.openHat, _Shape.hihat, 0.10, 0.34, 0.10, _kBrass),
  _Piece(Drum.hat, _Shape.hihat, 0.11, 0.52, 0.10, _kBrass),
  // Toms: high → mid across the top of the kick, floor tom to the right.
  _Piece(Drum.highTom, _Shape.tom, 0.40, 0.36, 0.10, _kTom),
  _Piece(Drum.tom, _Shape.tom, 0.56, 0.35, 0.11, _kTom),
  _Piece(Drum.lowTom, _Shape.tom, 0.87, 0.60, 0.13, _kTom),
  // Snare + the big front kick.
  _Piece(Drum.snare, _Shape.snare, 0.31, 0.62, 0.12, _kShell),
  _Piece(Drum.kick, _Shape.kick, 0.53, 0.76, 0.20, _kShell),
  // Small hand-percussion accents in the gaps.
  _Piece(Drum.clap, _Shape.puck, 0.44, 0.55, 0.055, Color(0xFFE0A96D)),
  _Piece(Drum.rim, _Shape.puck, 0.20, 0.80, 0.05, Color(0xFF9AA0A6)),
  _Piece(Drum.cowbell, _Shape.puck, 0.68, 0.53, 0.05, Color(0xFFB08D57)),
];

class _DrumKitPainter extends CustomPainter {
  _DrumKitPainter({
    required this.glow,
    required this.drums,
    required this.dark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Map<Drum, double> glow;
  final List<Drum> drums;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = drums.toSet();
    final s = size.shortestSide;
    for (final p in _kLayout) {
      if (!shown.contains(p.drum)) continue;
      final c = Offset(p.cx * size.width, p.cy * size.height);
      final r = p.r * s;
      final g = (glow[p.drum] ?? 0).clamp(0.0, 1.0);
      switch (p.shape) {
        case _Shape.cymbal:
        case _Shape.hihat:
          _cymbal(canvas, c, r, p.color, g, hat: p.shape == _Shape.hihat);
        case _Shape.tom:
        case _Shape.snare:
        case _Shape.kick:
          _drum(canvas, c, r, p.color, g, front: p.shape == _Shape.kick);
        case _Shape.puck:
          _puck(canvas, c, r, p.color, g);
      }
    }
  }

  // A cymbal: a flat tilted ellipse on a thin stand, with a centre bell.
  void _cymbal(
    Canvas canvas,
    Offset c,
    double r,
    Color base,
    double g, {
    required bool hat,
  }) {
    final stand = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.25)
      ..strokeWidth = max(1.0, r * 0.06);
    canvas.drawLine(c, Offset(c.dx, c.dy + r * 1.7), stand);
    final rect = Rect.fromCenter(center: c, width: r * 2, height: r * 0.7);
    if (g > 0) _halo(canvas, c, r * 1.4, g);
    canvas.drawOval(
      rect,
      Paint()..color = Color.lerp(base, Colors.white, 0.15 + 0.7 * g)!,
    );
    // A darker rim ring + the bell, so it reads as brass not a blob.
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.05)
        ..color = Colors.black.withValues(alpha: 0.25),
    );
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 0.5, height: r * 0.22),
      Paint()..color = Color.lerp(base, Colors.black, 0.2)!,
    );
    if (hat) {
      // A second (lower) plate marks the hi-hat pair.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy + r * 0.28),
          width: r * 1.9,
          height: r * 0.5,
        ),
        Paint()..color = Color.lerp(base, Colors.black, 0.25)!,
      );
    }
  }

  // A drum: an elliptical head (perspective-squashed) with a rim + shell.
  void _drum(
    Canvas canvas,
    Offset c,
    double r,
    Color shell,
    double g, {
    required bool front,
  }) {
    final h = front ? r * 1.7 : r * 1.1; // the kick faces us (rounder)
    final rect = Rect.fromCenter(center: c, width: r * 2, height: h);
    if (g > 0) _halo(canvas, c, r * 1.2, g);
    // Shell body (a soft vertical shade).
    canvas.drawOval(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(shell, Colors.white, 0.25)!,
            Color.lerp(shell, Colors.black, 0.2)!,
          ],
        ).createShader(rect),
    );
    // Head (lighter, flares bright when struck).
    final head = Rect.fromCenter(
      center: c,
      width: r * 1.7,
      height: h * 0.82,
    );
    canvas.drawOval(
      head,
      Paint()
        ..color = Color.lerp(
          const Color(0xFFF2E9D8),
          Colors.white,
          0.9 * g,
        )!
            .withValues(alpha: 0.92),
    );
    // Rim.
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.5, r * 0.1)
        ..color = Color.lerp(shell, Colors.black, 0.3)!,
    );
  }

  // A small labelled accent puck (clap / rim / cowbell).
  void _puck(Canvas canvas, Offset c, double r, Color base, double g) {
    if (g > 0) _halo(canvas, c, r * 1.3, g);
    canvas.drawCircle(
      c,
      r,
      Paint()..color = Color.lerp(base, Colors.white, 0.8 * g)!,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.14)
        ..color = Colors.black.withValues(alpha: 0.3),
    );
  }

  // A soft additive halo behind a struck piece.
  void _halo(Canvas canvas, Offset c, double r, double g) {
    canvas.drawCircle(
      c,
      r * (1.0 + 0.3 * g),
      Paint()
        ..color = const Color(0xFFFFF3B0).withValues(alpha: 0.55 * g)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );
  }

  @override
  bool shouldRepaint(_DrumKitPainter old) =>
      old.dark != dark || old.drums != drums;
}
