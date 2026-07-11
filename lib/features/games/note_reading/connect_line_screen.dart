// lib/features/games/note_reading/connect_line_screen.dart
//
// "Verbinde die Noten" / "Connect the Notes" — a connect-a-line matching drill
// (docs/PLAN.md gamified backlog, the last of the surveyed interaction
// mechanics). Two columns: notes on real partitura staves on the left, their
// letter names (shuffled) on the right. The child drags a line from a note to
// its name; a correct link locks in colour and plays the pitch, a wrong drop
// buzzes and snaps back (the app's no-fail loop). Match all four to clear the
// round.
//
// SRI: 'note_reading.treble.<step><octave>' — the shared reading namespace, so
// each first-try link feeds the SM-2 engine.

import 'dart:math';

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_colors.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/widgets/game_widgets.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

class ConnectLineScreen extends StatefulWidget {
  const ConnectLineScreen({super.key});

  /// Pairs to connect per round.
  static const pairs = 4;

  static const _cardW = 92.0;
  static const _chipW = 92.0;
  static const _pad = 12.0;

  /// Key on the drag board, so tests can locate its rect for gestures.
  @visibleForTesting
  static const boardKey = ValueKey('connect_board');

  @override
  State<ConnectLineScreen> createState() => _ConnectLineScreenState();
}

/// Typed window into the game for widget tests (the state class is private).
@visibleForTesting
abstract interface class ConnectLineTester {
  int get score;
  bool get finished;
  int get round;
  int get matchedCount;

  /// The right-column index whose name matches left note [leftIndex].
  int matchingRight(int leftIndex);
}

class _ConnectLineScreenState extends State<ConnectLineScreen>
    with QuizRoundMixin
    implements ConnectLineTester {
  final _random = Random();

  @override
  int get matchedCount => _matched.length;

  @override
  int matchingRight(int leftIndex) =>
      _rights.indexWhere((p) => p.step == _lefts[leftIndex].step);

  late List<Pitch> _lefts; // notes, top → bottom
  late List<Pitch> _rights; // the same notes, shuffled, shown as names
  final Map<int, int> _matched = {}; // left index → right index (locked)
  final Set<int> _recorded = {}; // left indices already scored into SRI

  int? _dragFrom; // left index being dragged
  Offset? _dragPos; // current finger position (local)

  @override
  int get totalRounds => 6;

  @override
  String get gameType => 'connect_line';

  // We play each linked note's own pitch (and a buzz on a miss).
  @override
  bool get playFeedbackSounds => false;

  @override
  void initState() {
    super.initState();
    prepareRound();
  }

  @override
  void prepareRound() {
    // Four notes with *distinct* step letters, so every name on the right is
    // unique and a link is unambiguous. Star-driven width, like the reading
    // quizzes: naturals on the staff → the middle-C ledger neighbourhood.
    final wide = context.read<ProgressService>().starsFor('connect_line') >= 2;
    final pool = [for (var p = wide ? -3 : 0; p <= (wide ? 10 : 8); p++) p]
      ..shuffle(_random);

    final picked = <Pitch>[];
    final usedSteps = <Step>{};
    for (final p in pool) {
      final pitch = Clef.treble.pitchAt(p);
      if (usedSteps.add(pitch.step)) {
        picked.add(pitch);
        if (picked.length == ConnectLineScreen.pairs) break;
      }
    }

    _lefts = picked;
    _rights = [...picked]..shuffle(_random);
    _matched.clear();
    _recorded.clear();
    _dragFrom = null;
    _dragPos = null;
  }

  String _sriId(Pitch p) => 'note_reading.treble.${p.step.name}${p.octave}';

  void _tryConnect(int leftIndex, int rightIndex) {
    final correct = _lefts[leftIndex].step == _rights[rightIndex].step;

    // Score the read into SM-2 on the first attempt for this note.
    if (_recorded.add(leftIndex)) {
      context.read<SriService>().recordResponse(
            _sriId(_lefts[leftIndex]),
            correct,
          );
    }

    if (correct) {
      context
          .read<AudioService>()
          .playMidiNote(_lefts[leftIndex].midiNumber, ms: 450);
      setState(() => _matched[leftIndex] = rightIndex);
      if (_matched.length == ConnectLineScreen.pairs) {
        resolveAnswer(correct: true); // round cleared
      }
    } else {
      context.read<AudioService>().playWrong();
      setState(() => answeredWrong = true);
    }
  }

  // --- Gesture → anchors (row bands, forgiving for small hands) --------------

  void _onPanStart(Offset local, Size size) {
    final rowH = size.height / ConnectLineScreen.pairs;
    final i = (local.dy ~/ rowH).clamp(0, ConnectLineScreen.pairs - 1);
    if (local.dx < size.width / 2 && !_matched.containsKey(i)) {
      setState(() {
        _dragFrom = i;
        _dragPos = local;
      });
    }
  }

  void _onPanUpdate(Offset local) {
    if (_dragFrom != null) setState(() => _dragPos = local);
  }

  void _onPanEnd(Size size) {
    final from = _dragFrom;
    final pos = _dragPos;
    if (from != null && pos != null) {
      final rowH = size.height / ConnectLineScreen.pairs;
      final j = (pos.dy ~/ rowH).clamp(0, ConnectLineScreen.pairs - 1);
      final rightTaken = _matched.values.contains(j);
      if (pos.dx > size.width / 2 && !rightTaken) {
        _tryConnect(from, j);
      }
    }
    setState(() {
      _dragFrom = null;
      _dragPos = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScaffold = context.watch<SettingsService>().colorScaffold;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameConnectLine)),
      body: SafeArea(
        child: finished
            ? GameResultView(
                gameType: gameType,
                score: score,
                onRestart: restartGame,
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    RoundHeader(
                      round: round + 1,
                      totalRounds: totalRounds,
                      prompt: l10n.connectLinePrompt,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.biggest;
                          return _buildBoard(context, size, colorScaffold);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    FeedbackLine(
                      correct: _matched.length == ConnectLineScreen.pairs
                          ? true
                          : (answeredWrong ? false : null),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context, Size size, bool colorScaffold) {
    final rowH = size.height / ConnectLineScreen.pairs;
    const leftPortX = ConnectLineScreen._pad + ConnectLineScreen._cardW;
    final rightPortX =
        size.width - ConnectLineScreen._pad - ConnectLineScreen._chipW;

    return GestureDetector(
      key: ConnectLineScreen.boardKey,
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _onPanStart(d.localPosition, size),
      onPanUpdate: (d) => _onPanUpdate(d.localPosition),
      onPanEnd: (_) => _onPanEnd(size),
      child: Stack(
        children: [
          // Left column: notes on staves.
          for (var i = 0; i < _lefts.length; i++)
            Positioned(
              left: ConnectLineScreen._pad,
              top: i * rowH,
              width: ConnectLineScreen._cardW,
              height: rowH,
              child: _NoteCard(
                pitch: _lefts[i],
                connected: _matched.containsKey(i),
                active: _dragFrom == i,
              ),
            ),
          // Right column: the names.
          for (var j = 0; j < _rights.length; j++)
            Positioned(
              right: ConnectLineScreen._pad,
              top: j * rowH,
              width: ConnectLineScreen._chipW,
              height: rowH,
              child: _NameChip(
                label: noteNameFor(context, _rights[j].step),
                color: colorScaffold
                    ? pitchClassColor(_rights[j].step)
                    : Theme.of(context).colorScheme.secondary,
                connected: _matched.values.contains(j),
              ),
            ),
          // The lines + ports, drawn on top so a link is always visible.
          Positioned.fill(
            child: CustomPaint(
              painter: _WirePainter(
                pairs: ConnectLineScreen.pairs,
                rowH: rowH,
                leftPortX: leftPortX,
                rightPortX: rightPortX,
                matched: Map.of(_matched),
                leftSteps: [for (final p in _lefts) p.step],
                dragFrom: _dragFrom,
                dragPos: _dragPos,
                colorScaffold: colorScaffold,
                lineColor: Theme.of(context).colorScheme.primary,
                portColor: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.pitch,
    required this.connected,
    required this.active,
  });

  final Pitch pitch;
  final bool connected;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = connected
        ? Colors.green
        : active
            ? scheme.primary
            : scheme.outlineVariant;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color:
            connected ? Colors.green.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: border, width: connected || active ? 2.5 : 1.5),
      ),
      child: Center(
        child: StaffView(
          score: Score.simple(notes: '${pitch.step.name}${pitch.octave}:w'),
          staffSpace: 7,
          theme: PartituraTheme.kids,
        ),
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({
    required this.label,
    required this.color,
    required this.connected,
  });

  final String label;
  final Color color;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: connected ? 0.85 : 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? Colors.green : color,
          width: connected ? 2.5 : 1.5,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: connected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
        ),
      ),
    );
  }
}

/// Draws the locked links, the in-progress drag line, and the connection ports.
class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.pairs,
    required this.rowH,
    required this.leftPortX,
    required this.rightPortX,
    required this.matched,
    required this.leftSteps,
    required this.dragFrom,
    required this.dragPos,
    required this.colorScaffold,
    required this.lineColor,
    required this.portColor,
  });

  final int pairs;
  final double rowH;
  final double leftPortX;
  final double rightPortX;
  final Map<int, int> matched;
  final List<Step> leftSteps;
  final int? dragFrom;
  final Offset? dragPos;
  final bool colorScaffold;
  final Color lineColor;
  final Color portColor;

  double _rowCenter(int index) => index * rowH + rowH / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final portStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = portColor;
    final portFill = Paint()..color = portColor.withValues(alpha: 0.35);

    // Ports.
    for (var i = 0; i < pairs; i++) {
      canvas.drawCircle(Offset(leftPortX, _rowCenter(i)), 6, portFill);
      canvas.drawCircle(Offset(leftPortX, _rowCenter(i)), 6, portStroke);
      canvas.drawCircle(Offset(rightPortX, _rowCenter(i)), 6, portFill);
      canvas.drawCircle(Offset(rightPortX, _rowCenter(i)), 6, portStroke);
    }

    // Locked links.
    matched.forEach((i, j) {
      final c = colorScaffold ? pitchClassColor(leftSteps[i]) : Colors.green;
      final paint = Paint()
        ..color = c
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final a = Offset(leftPortX, _rowCenter(i));
      final b = Offset(rightPortX, _rowCenter(j));
      canvas.drawLine(a, b, paint);
      canvas.drawCircle(a, 6, Paint()..color = c);
      canvas.drawCircle(b, 6, Paint()..color = c);
    });

    // The line being dragged.
    if (dragFrom != null && dragPos != null) {
      final paint = Paint()
        ..color = lineColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(leftPortX, _rowCenter(dragFrom!)),
        dragPos!,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WirePainter old) =>
      old.matched.length != matched.length ||
      old.dragFrom != dragFrom ||
      old.dragPos != dragPos;
}
