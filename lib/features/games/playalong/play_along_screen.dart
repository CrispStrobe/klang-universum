// lib/features/games/playalong/play_along_screen.dart
//
// Play-along / sing-along with a MOVING SCORE. Target notes scroll right-to-left
// past a fixed "now" line; your live pitch is drawn as a dot so you can see
// yourself land on (or drift from) each note. Scoring is delegated to the pure
// PlayAlongEngine; this screen only drives the clock (a Ticker), feeds it the
// mic's readings, and paints.
//
// One screen serves both modes — pass a cello chart for play-along or an
// octave-agnostic vocal chart for sing-along. Not yet localized (see PLAN.md);
// no audible backing on purpose (the mic would hear the speaker — use the
// Preview button, then play/sing against the scroll).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:klang_universum/core/audio/microphone_pitch_service.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/audio/play_along.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:provider/provider.dart';

const _noteNames = <String>[
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
String _midiName(int m) => '${_noteNames[m % 12]}${(m ~/ 12) - 1}';

class PlayAlongScreen extends StatefulWidget {
  const PlayAlongScreen({
    super.key,
    required this.chart,
    required this.title,
  });

  final PlayAlongChart chart;
  final String title;

  @override
  State<PlayAlongScreen> createState() => _PlayAlongScreenState();
}

class _PlayAlongScreenState extends State<PlayAlongScreen>
    with SingleTickerProviderStateMixin {
  final MicrophonePitchService _service = MicrophonePitchService();
  late final Ticker _ticker;
  StreamSubscription<PitchReading>? _sub;
  late PlayAlongEngine _engine = PlayAlongEngine(widget.chart);

  PitchReading _latest = PitchReading.silent();
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Create the ticker eagerly so it is never lazily created during dispose
    // (which would look up an ancestor on a deactivated element).
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _engine.update(
      elapsedMs: elapsed.inMicroseconds / 1000.0,
      reading: _latest,
    );
    if (_engine.finished) {
      _stop();
    } else {
      setState(() {});
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _engine = PlayAlongEngine(widget.chart);
    });
    try {
      _sub = _service.readings.listen(
        (r) => _latest = r,
        onError: (Object e) {
          if (mounted) setState(() => _error = '$e');
        },
      );
      await _service.start();
      unawaited(_ticker.start()); // TickerFuture completes only when stopped
      if (mounted) setState(() => _running = true);
    } on PitchCaptureException catch (e) {
      await _sub?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
          _error = switch (e.reason) {
            PitchCaptureError.permissionDenied =>
              'Microphone permission denied. Enable it in system settings.',
            _ => 'Could not start the microphone: ${e.detail ?? e.reason.name}',
          };
        });
      }
    }
  }

  Future<void> _stop() async {
    _ticker.stop();
    await _service.stop();
    await _sub?.cancel();
    _latest = PitchReading.silent();
    if (mounted) setState(() => _running = false);
  }

  void _preview() {
    context.read<AudioService>().playSequence([
      for (final n in widget.chart.notes)
        (n.midi, (n.beats * widget.chart.beatMs).round()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _engine.activeNote;
    final liveMidi = _latest.hasPitch ? _latest.midi : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat(
                    context,
                    'Score',
                    '${_engine.hits}/${_engine.notes.length}',
                  ),
                  _stat(
                    context,
                    'Now',
                    _running
                        ? (_engine.inCountIn
                            ? 'count-in'
                            : (active != null
                                ? _midiName(active.note.midi)
                                : '—'))
                        : '—',
                  ),
                  _stat(
                    context,
                    'You',
                    _latest.hasPitch ? _latest.noteName : '—',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CustomPaint(
                  painter: _HighwayPainter(
                    engine: _engine,
                    liveMidi: liveMidi,
                    onPitch: active != null &&
                        _latest.hasPitch &&
                        _latest.cents.abs() <= _engine.centsTolerance &&
                        (widget.chart.octaveAgnostic
                            ? _latest.nearestMidi % 12 == active.note.midi % 12
                            : _latest.nearestMidi == active.note.midi),
                    scheme: scheme,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _running ? null : _preview,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Preview'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _running ? _stop : _start,
                    icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                    label: Text(_running ? 'Stop' : 'Play along'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _HighwayPainter extends CustomPainter {
  _HighwayPainter({
    required this.engine,
    required this.liveMidi,
    required this.onPitch,
    required this.scheme,
  });

  final PlayAlongEngine engine;
  final double? liveMidi;
  final bool onPitch;
  final ColorScheme scheme;

  static const double _beatsVisible = 8; // how many beats span the width
  static const double _nowFrac = 0.28; // where "now" sits, left-ish

  @override
  void paint(Canvas canvas, Size size) {
    final notes = engine.chart.notes;
    if (notes.isEmpty) return;

    // Pitch range with padding.
    var lo = notes.first.midi, hi = notes.first.midi;
    for (final n in notes) {
      lo = n.midi < lo ? n.midi : lo;
      hi = n.midi > hi ? n.midi : hi;
    }
    lo -= 3;
    hi += 3;
    final span = (hi - lo).toDouble();
    double y(num midi) => size.height - (midi - lo) / span * size.height;

    final pxPerBeat = size.width / _beatsVisible;
    final nowX = size.width * _nowFrac;
    final beat = engine.currentBeat;
    double x(double b) => nowX + (b - beat) * pxPerBeat;
    final semi = size.height / span;
    final barH = (semi * 0.8).clamp(6.0, 22.0);

    // Faint lane lines every octave.
    final lane = Paint()..color = scheme.onSurface.withValues(alpha: 0.06);
    for (var m = lo - (lo % 12); m <= hi; m += 12) {
      canvas.drawRect(Rect.fromLTWH(0, y(m) - 0.5, size.width, 1), lane);
    }

    // Notes.
    for (final ns in engine.notes) {
      final n = ns.note;
      final left = x(n.startBeat);
      final right = x(n.endBeat);
      if (right < 0 || left > size.width) continue;
      final color = switch (ns.result) {
        NoteResult.hit => Colors.green,
        NoteResult.missed => scheme.error,
        NoteResult.pending => ns == engine.activeNote
            ? scheme.primary
            : scheme.primary.withValues(alpha: 0.45),
      };
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left + 1,
          y(n.midi) - barH / 2,
          right - 1,
          y(n.midi) + barH / 2,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = color);
    }

    // "Now" line.
    canvas.drawLine(
      Offset(nowX, 0),
      Offset(nowX, size.height),
      Paint()
        ..color = scheme.onSurface.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );

    // Live pitch dot at the now line.
    if (liveMidi != null) {
      final ly = y(liveMidi!.clamp(lo.toDouble(), hi.toDouble()));
      final p = Paint()..color = onPitch ? Colors.green : Colors.amber;
      canvas.drawCircle(Offset(nowX, ly), 9, p);
      canvas.drawCircle(
        Offset(nowX, ly),
        13,
        Paint()
          ..color = p.color.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_HighwayPainter old) => true; // driven by the ticker
}
