// lib/features/games/composition/advanced_tracker_screen.dart
//
// The Tracker's ADVANCED mode — a classic ProTracker / Scream Tracker 3 /
// Impulse Tracker / FastTracker 2 style pattern editor, in contrast to the
// Beginner mode (tracker_screen.dart, a scale-locked kid grid capped at one
// bar). It drops every kid limit:
//
//   * endless pattern length  (the "Length" control — no more 2-3 Takte),
//   * endless tracks          ("Add track" / per-track remove),
//   * chromatic entry          (tap a cell -> full-range note picker, no
//                               pentatonic snapping),
//   * a rows x channels grid   with hex row numbers and a moving playhead.
//
// It drives the general [TrackerSong] document over the shared [TrackerEngine]
// (same offline mixStems -> one looping WAV -> GaplessLoopPlayer path the
// Beginner grid and Loop Mixer use; the Stopwatch owns the musical phase so an
// edit re-swaps the loop without the beat restarting; a Ticker created in
// initState — never a lazy `late final`, see CLAUDE.md — drives the playhead).
//
// Slice 1 ships the grid, endless length + tracks, tap-to-place chromatic notes,
// and Play/Stop. Computer-keyboard entry, the note/instrument/volume/effect
// sub-columns, multi-pattern songs + order list, and the full transport
// (pause/prev/next/loop) land in later slices — all over this same document.

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/composition/tracker_screen.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

/// Note names for chromatic display, classic-tracker style ("C-4", "C#4").
const _kNoteNames = [
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

/// A MIDI number as a tracker note label, e.g. 60 -> "C-4", 61 -> "C#4".
String trackerNoteName(int midi) {
  final name = _kNoteNames[midi % 12];
  final octave = midi ~/ 12 - 1;
  return name.length == 1 ? '$name-$octave' : '$name$octave';
}

/// Selectable pattern lengths (rows). "Endless" in practice — the grid handles
/// any of these, well past the Beginner grid's single bar.
const _kLengthOptions = [16, 32, 48, 64, 96, 128];

class AdvancedTrackerScreen extends StatefulWidget {
  const AdvancedTrackerScreen({super.key});

  @override
  State<AdvancedTrackerScreen> createState() => _AdvancedTrackerScreenState();
}

/// Test handle onto the running screen (the state class is private) — mirrors
/// [TrackerTester] on the Beginner screen.
@visibleForTesting
abstract interface class AdvancedTrackerTester {
  int get channelCount;
  int get rows;
  int get noteCount;
  bool get isPlaying;

  /// Place [midi] at [channel]/[row] (chromatic, no snapping).
  void setNote(int channel, int row, int midi);
  void clearNote(int channel, int row);
  void setRows(int rows);
  void addTrack();
  void removeTrack(int channel);
  void togglePlay();
}

class _AdvancedTrackerScreenState extends State<AdvancedTrackerScreen>
    with SingleTickerProviderStateMixin
    implements AdvancedTrackerTester {
  final _song = TrackerSong();
  final _loop = GaplessLoopPlayer();

  /// The musical clock — playback phase derives from it, never the player, so an
  /// edit re-enters the loop in phase.
  final _clock = Stopwatch();
  late final Ticker _ticker;

  /// The sounding row (0-based), or -1 when stopped. Drives the playhead without
  /// a full rebuild.
  final _row = ValueNotifier<int>(-1);

  final _vScroll = ScrollController();
  int _lastFollowedRow = -1;

  static const _rowNumWidth = 44.0;
  static const _cellWidth = 66.0;
  static const _rowHeight = 30.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!_clock.isRunning) {
        if (_row.value != -1) _row.value = -1;
        return;
      }
      final t = _song.timing;
      final step = (_clock.elapsedMilliseconds % t.totalMs) ~/ t.stepMs;
      if (step != _row.value) {
        _row.value = step;
        _followPlayhead(step);
      }
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _row.dispose();
    _vScroll.dispose();
    _loop.dispose();
    super.dispose();
  }

  // --- AdvancedTrackerTester ---
  @override
  int get channelCount => _song.channelCount;
  @override
  int get rows => _song.rows;
  @override
  // Reads the engine's LIVE cells (the working copy of the current pattern) —
  // the pattern snapshot only catches up on syncCurrent().
  int get noteCount => _song.engine.channels
      .fold(0, (n, c) => n + c.cells.where((cell) => !cell.isEmpty).length);
  @override
  bool get isPlaying => _clock.isRunning;
  @override
  void setNote(int channel, int row, int midi) =>
      _setCell(channel, row, TrackerCell(midi: midi));
  @override
  void clearNote(int channel, int row) =>
      _setCell(channel, row, TrackerCell.empty);
  @override
  void setRows(int rows) {
    setState(() => _song.setRows(rows));
    _syncPlayback();
  }

  @override
  void addTrack() {
    setState(_song.addChannel);
    _syncPlayback();
  }

  @override
  void removeTrack(int channel) {
    setState(() => _song.removeChannel(channel));
    _syncPlayback();
  }

  @override
  void togglePlay() => _togglePlay();

  // --- Editing ---

  void _setCell(int channel, int row, TrackerCell cell) {
    setState(() => _song.engine.setCell(channel, row, cell));
    _syncPlayback();
  }

  void _clearAll() {
    setState(_song.engine.clearAll);
    _syncPlayback();
  }

  // --- Playback (mirrors tracker_screen.dart's phase-preserving loop swap) ---

  void _togglePlay() {
    if (_clock.isRunning) {
      _clock
        ..stop()
        ..reset();
      _loop.stop();
      _row.value = -1;
      setState(() {});
    } else {
      _clock
        ..reset()
        ..start();
      _syncPlayback();
      setState(() {});
    }
  }

  /// Swaps/stops the looping mix to match the current pattern, keeping the
  /// musical phase so an edit never resets the beat.
  void _syncPlayback() {
    if (!_clock.isRunning) return;
    if (_song.current.hasAnyNote == false) {
      _loop.stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return; // master mute
    final wav = _song.renderCurrentPatternWav();
    final position = Duration(
      milliseconds: _clock.elapsedMilliseconds % _song.timing.totalMs,
    );
    _loop.playLoop(wav, position: position);
  }

  void _followPlayhead(int step) {
    if (!_vScroll.hasClients || step == _lastFollowedRow) return;
    _lastFollowedRow = step;
    final target = (step * _rowHeight) - 120;
    final max = _vScroll.position.maxScrollExtent;
    _vScroll.jumpTo(target.clamp(0.0, max));
  }

  // --- Note picker (chromatic; Slice 2 adds keyboard entry + sub-columns) ---

  Future<void> _pickNote(int channel, int row) async {
    final l10n = AppLocalizations.of(context)!;
    final current = _song.engine.cellAt(channel, row).midi;
    var octave = current != null ? current ~/ 12 - 1 : 4;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.trackerPickNote} — ${_song.channels[channel].id}',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('${l10n.trackerOctave}: '),
                    for (var o = 1; o <= 7; o++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ChoiceChip(
                          label: Text('$o'),
                          selected: o == octave,
                          onSelected: (_) => setSheet(() => octave = o),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var semi = 0; semi < 12; semi++)
                      ActionChip(
                        label: Text(_kNoteNames[semi]),
                        onPressed: () {
                          _setCell(
                            channel,
                            row,
                            TrackerCell(midi: (octave + 1) * 12 + semi),
                          );
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.backspace_outlined, size: 16),
                      label: Text(l10n.trackerClear),
                      onPressed: () {
                        clearNote(channel, row);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toBeginner() => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TrackerScreen()),
      );

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: GameAppBar(
        title: l10n.trackerAdvancedTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.child_care),
            tooltip: l10n.trackerModeToBeginner,
            onPressed: _toBeginner,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.trackerClear,
            onPressed: _clearAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _togglePlay,
        tooltip: _clock.isRunning ? l10n.trackerStop : l10n.trackerPlay,
        child: Icon(_clock.isRunning ? Icons.stop : Icons.play_arrow),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _toolbar(l10n),
            const Divider(height: 1),
            Expanded(child: _grid(context)),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Endless length — the direct fix for "stops after 2-3 Takte".
            Text('${l10n.trackerLength}: '),
            DropdownButton<int>(
              value: _kLengthOptions.contains(_song.rows) ? _song.rows : null,
              hint: Text('${_song.rows}'),
              items: [
                for (final n in _kLengthOptions)
                  DropdownMenuItem(value: n, child: Text('$n')),
              ],
              onChanged: (v) {
                if (v != null) setRows(v);
              },
            ),
            const SizedBox(width: 20),
            // Endless tracks.
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.trackerAddTrack),
              onPressed: addTrack,
            ),
            const SizedBox(width: 12),
            Text(
              '${_song.channelCount} × ${_song.rows}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepsPerBeat = _song.timing.stepsPerBeat;
    final gridWidth = _rowNumWidth + _song.channelCount * _cellWidth;

    return Scrollbar(
      controller: _vScroll,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: gridWidth,
          child: Column(
            children: [
              _headerRow(scheme),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _row,
                  builder: (context, activeRow, _) => ListView.builder(
                    controller: _vScroll,
                    itemExtent: _rowHeight,
                    itemCount: _song.rows,
                    itemBuilder: (context, row) =>
                        _rowWidget(row, activeRow, stepsPerBeat, scheme),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(ColorScheme scheme) {
    return Container(
      height: _rowHeight,
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          const SizedBox(width: _rowNumWidth),
          for (var c = 0; c < _song.channelCount; c++)
            SizedBox(
              width: _cellWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _song.channels[c].id,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_song.channelCount > 1)
                    InkWell(
                      onTap: () => removeTrack(c),
                      child: const Icon(Icons.close, size: 13),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowWidget(
    int row,
    int activeRow,
    int stepsPerBeat,
    ColorScheme scheme,
  ) {
    final isActive = row == activeRow;
    final isBeat = row % stepsPerBeat == 0;
    final rowBg = isActive
        ? scheme.primaryContainer
        : (isBeat ? scheme.surfaceContainerHighest : null);
    return Container(
      height: _rowHeight,
      color: rowBg,
      child: Row(
        children: [
          SizedBox(
            width: _rowNumWidth,
            child: Text(
              row.toString().padLeft(2, '0'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontSize: 12,
                color: isBeat ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: isBeat ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          for (var c = 0; c < _song.channelCount; c++)
            _cell(c, row, isActive, scheme),
        ],
      ),
    );
  }

  Widget _cell(int channel, int row, bool isActiveRow, ColorScheme scheme) {
    final cell = _song.engine.cellAt(channel, row);
    final text = cell.midi != null ? trackerNoteName(cell.midi!) : '···';
    return GestureDetector(
      onTap: () => _pickNote(channel, row),
      onLongPress: () => clearNote(channel, row),
      child: Container(
        width: _cellWidth,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 14,
            color: cell.midi != null
                ? scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.4),
            fontWeight: cell.midi != null ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
