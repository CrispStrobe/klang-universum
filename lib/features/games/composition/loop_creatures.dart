// lib/features/games/composition/loop_creatures.dart
//
// The Loop Mixer's band as little "shape-creatures": each track is a friendly
// shape whose form nods to its instrument (a drumhead, a speaker, piano keys, a
// note, a star, a mic, an equalizer), with a face that's awake and smiling when
// the layer plays and asleep when it's off. Drawn procedurally (no art assets);
// the pure id→shape mapping unit-tests, the look is verified by a render check.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The creature body forms, one per Loop Mixer layer.
enum CreatureShape { drum, bass, keys, note, star, mic, bars }

/// The creature shape for a track id (falls back to a note for anything else).
CreatureShape creatureShapeFor(String id) => switch (id) {
      'drums' => CreatureShape.drum,
      'bass' => CreatureShape.bass,
      'chords' => CreatureShape.keys,
      'melody' => CreatureShape.note,
      'sparkle' => CreatureShape.star,
      'voice' => CreatureShape.mic,
      'beat' => CreatureShape.bars,
      _ => CreatureShape.note,
    };

/// A procedurally-drawn band member. [color] is the body colour; the face is
/// drawn in translucent ink so it reads on any body. Awake + smiling when
/// [active], asleep otherwise. Beat-bob comes from the enclosing card pulse.
class LoopCreature extends StatelessWidget {
  const LoopCreature({
    super.key,
    required this.shape,
    required this.active,
    required this.color,
    this.size = 34,
  });

  final CreatureShape shape;
  final bool active;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _CreaturePainter(shape: shape, active: active, color: color),
      );
}

class _CreaturePainter extends CustomPainter {
  _CreaturePainter({
    required this.shape,
    required this.active,
    required this.color,
  });

  final CreatureShape shape;
  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h * 0.54;
    final body = Paint()..color = color;
    final ink = Paint()..color = const Color(0xB3151522);
    final inkStroke = Paint()
      ..color = const Color(0xB3151522)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = w * 0.40;

    // --- Body + a small musical accent per instrument ---
    switch (shape) {
      case CreatureShape.drum:
        canvas.drawCircle(Offset(cx, cy), r, body);
        canvas.drawLine(
          Offset(cx - r * 0.15, cy - r * 1.5),
          Offset(cx - r * 0.55, cy - r * 0.6),
          inkStroke,
        );
        canvas.drawLine(
          Offset(cx + r * 0.15, cy - r * 1.5),
          Offset(cx + r * 0.55, cy - r * 0.6),
          inkStroke,
        );
      case CreatureShape.bass:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 0.92,
              height: h * 0.66,
            ),
            Radius.circular(w * 0.26),
          ),
          body,
        );
      case CreatureShape.keys:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 0.86,
              height: h * 0.7,
            ),
            Radius.circular(w * 0.16),
          ),
          body,
        );
        for (final dx in [-0.26, 0.0, 0.26]) {
          canvas.drawLine(
            Offset(cx + dx * w, cy + r * 0.25),
            Offset(cx + dx * w, cy + r * 0.85),
            inkStroke,
          );
        }
      case CreatureShape.note:
        canvas.drawCircle(Offset(cx - r * 0.15, cy), r, body);
        canvas.drawLine(
          Offset(cx + r * 0.7, cy - r * 0.1),
          Offset(cx + r * 0.7, cy - r * 1.7),
          inkStroke,
        );
      case CreatureShape.star:
        _drawStar(canvas, Offset(cx, cy), r * 1.25, body);
      case CreatureShape.mic:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy - h * 0.04),
              width: w * 0.52,
              height: h * 0.72,
            ),
            Radius.circular(w * 0.26),
          ),
          body,
        );
      case CreatureShape.bars:
        for (var i = 0; i < 4; i++) {
          final bh = h * (0.30 + 0.11 * (i.isEven ? 1 : 2));
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                w * 0.16 + i * w * 0.19,
                cy + h * 0.30 - bh,
                w * 0.12,
                bh,
              ),
              Radius.circular(w * 0.04),
            ),
            body,
          );
        }
    }

    // --- Face --- (bars host it above their bars; others on the body)
    final faceY = switch (shape) {
      CreatureShape.bars => cy - h * 0.30,
      CreatureShape.star => cy - r * 0.05,
      _ => cy - r * 0.12,
    };
    final eyeDx = w * (shape == CreatureShape.bars ? 0.1 : 0.14);
    if (active) {
      canvas
        ..drawCircle(Offset(cx - eyeDx, faceY), w * 0.05, ink)
        ..drawCircle(Offset(cx + eyeDx, faceY), w * 0.05, ink);
      final smile = Path()
        ..moveTo(cx - w * 0.11, faceY + h * 0.12)
        ..quadraticBezierTo(
          cx,
          faceY + h * 0.26,
          cx + w * 0.11,
          faceY + h * 0.12,
        );
      canvas.drawPath(smile, inkStroke);
    } else {
      for (final dx in [-eyeDx, eyeDx]) {
        final lid = Path()
          ..moveTo(cx + dx - w * 0.06, faceY)
          ..quadraticBezierTo(
            cx + dx,
            faceY + h * 0.05,
            cx + dx + w * 0.06,
            faceY,
          );
        canvas.drawPath(lid, inkStroke);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? r : r * 0.45;
      final p =
          Offset(c.dx + rad * math.cos(angle), c.dy + rad * math.sin(angle));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CreaturePainter old) =>
      old.active != active || old.color != color || old.shape != shape;
}
