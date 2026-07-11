// lib/shared/widgets/note_mascot.dart
//
// A little quarter-note character with a face, drawn in pure Dart (no assets).
// It hops + grins on a correct answer and gives a damped wobble + an "oops"
// mouth on a wrong one. Lives in the shared feedback line, so every game shows
// it. Respects reduced-motion.

import 'dart:math';

import 'package:flutter/material.dart';

enum NoteMascotMood { idle, happy, oops }

class NoteMascot extends StatefulWidget {
  final NoteMascotMood mood;
  final double size; // width; height is 1.4x

  const NoteMascot({super.key, required this.mood, this.size = 32});

  @override
  State<NoteMascot> createState() => _NoteMascotState();
}

class _NoteMascotState extends State<NoteMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void didUpdateWidget(NoteMascot old) {
    super.didUpdateWidget(old);
    // Re-play on every non-idle answer (including a repeated wrong tap).
    if (widget.mood != NoteMascotMood.idle) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = reduce ? 0.0 : _c.value;
        var scale = 1.0, angle = 0.0, dy = 0.0;
        switch (widget.mood) {
          case NoteMascotMood.happy:
            dy = -6 * sin(t * pi); // a hop
            scale = 1 + 0.18 * sin(t * pi);
          case NoteMascotMood.oops:
            angle = 0.18 * sin(t * pi * 4) * (1 - t); // damped wobble
          case NoteMascotMood.idle:
            break;
        }
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: CustomPaint(
                size: Size(widget.size, widget.size * 1.4),
                painter: _NotePainter(mood: widget.mood, color: color),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotePainter extends CustomPainter {
  final NoteMascotMood mood;
  final Color color;

  _NotePainter({required this.mood, required this.color});

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final fill = Paint()..color = color;
    final face = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;

    // Stem, then the tilted notehead.
    final stemW = w * 0.10;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.74, h * 0.10, stemW, h * 0.62),
        Radius.circular(stemW / 2),
      ),
      fill,
    );
    final head = Offset(w * 0.42, h * 0.74);
    c
      ..save()
      ..translate(head.dx, head.dy)
      ..rotate(-0.35)
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: w * 0.80, height: w * 0.66),
        fill,
      )
      ..restore();

    // Face, drawn upright on the notehead.
    final eyeY = head.dy - h * 0.03;
    final eyeR = w * 0.055;
    c.drawCircle(Offset(head.dx - w * 0.15, eyeY), eyeR, face);
    c.drawCircle(Offset(head.dx + w * 0.05, eyeY), eyeR, face);

    final mouth = Offset(head.dx - w * 0.05, head.dy + h * 0.05);
    switch (mood) {
      case NoteMascotMood.happy:
        c.drawArc(
          Rect.fromCenter(center: mouth, width: w * 0.26, height: h * 0.14),
          0.25,
          pi - 0.5,
          false,
          stroke,
        );
      case NoteMascotMood.oops:
        c.drawCircle(mouth, w * 0.06, stroke);
      case NoteMascotMood.idle:
        c.drawLine(
          mouth - Offset(w * 0.07, 0),
          mouth + Offset(w * 0.07, 0),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_NotePainter old) =>
      old.mood != mood || old.color != color;
}
