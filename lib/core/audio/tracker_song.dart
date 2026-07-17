// lib/core/audio/tracker_song.dart
//
// The Advanced Tracker's document model: a full "module" in the ProTracker /
// Scream Tracker 3 / Impulse Tracker / FastTracker 2 sense — an ordered list of
// PATTERNS played through a shared band of channels (instruments), with none of
// the kid-grid limits. Where the Beginner Tracker (tracker_screen.dart) hardcodes
// one 8-step bar × 5 pentatonic rows × 4 slots, a [TrackerSong] has:
//
//   * endless pattern length  (rows: any count, [setRows]),
//   * endless tracks          (channels: add/remove at runtime),
//   * a multi-pattern song    ([patterns] + an [order] list, like the classic
//                              order/sequence editor).
//
// It is a thin arrangement layer over the ALREADY-general [TrackerEngine] — the
// engine mixes one pattern's channels to a loop WAV (mixStems), and [renderSong]
// concatenates a snapshot per order-list entry. Flutter-free, so it unit-tests
// without a device (test/tracker_song_test.dart), exactly like the engine.
//
// Invariants (checked by asserts):
//   * patterns.isNotEmpty and order.isNotEmpty (a song always has something to
//     edit and to play),
//   * every pattern is channel-major with `channelCount` columns, each of length
//     `rows`,
//   * the engine's live channel cells ARE the current pattern's cells — editing
//     the engine edits [current]; [selectPattern] saves/loads snapshots.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// One pattern: a named, channel-major grid of cells (`cells[channel][row]`).
/// A snapshot compatible with [TrackerEngine.exportCells] /
/// [TrackerEngine.importCells].
class TrackerPattern {
  TrackerPattern({required this.name, required this.cells});

  /// A fresh empty pattern sized [channels] × [rows].
  TrackerPattern.empty({
    required this.name,
    required int channels,
    required int rows,
  }) : cells = [
          for (var c = 0; c < channels; c++)
            List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true),
        ];

  String name;

  /// Channel-major: `cells[channel]` is that channel's column of [rows] cells.
  final List<List<TrackerCell>> cells;

  int get channelCount => cells.length;
  int get rows => cells.isEmpty ? 0 : cells.first.length;

  bool get hasAnyNote => cells.any((col) => col.any((cell) => !cell.isEmpty));

  /// A deep copy (own cell lists) — so cloning a pattern never aliases cells.
  TrackerPattern clone({String? name}) => TrackerPattern(
        name: name ?? this.name,
        cells: [for (final col in cells) List<TrackerCell>.of(col)],
      );
}

/// The Advanced Tracker document. Owns a [TrackerEngine] (the band + the live
/// pattern being edited), the list of [patterns], and the [order] list.
class TrackerSong {
  TrackerSong._(this._engine, this.patterns, this.order, this._current);

  /// A new song with the default band ([defaultTrackerChannels]) and one empty
  /// pattern of [rows] steps at [timing].
  factory TrackerSong({
    List<TrackerChannel>? channels,
    TrackerTiming? timing,
    int patternCount = 1,
  }) {
    final t = timing ?? const TrackerTiming(rows: 32);
    final band = channels ?? defaultTrackerChannels(rows: t.rows);
    final engine = TrackerEngine(channels: band, timing: t);
    final patterns = [
      for (var i = 0; i < (patternCount < 1 ? 1 : patternCount); i++)
        TrackerPattern.empty(
          name: _patternName(i),
          channels: band.length,
          rows: t.rows,
        ),
    ];
    engine.importCells(patterns.first.cells);
    return TrackerSong._(engine, patterns, [0], 0);
  }

  TrackerEngine _engine;
  TrackerEngine get engine => _engine;

  /// All patterns (>= 1).
  final List<TrackerPattern> patterns;

  /// The order list: indices into [patterns], in play order (>= 1). May repeat.
  final List<int> order;

  int _current;

  // --- Read-only views ---------------------------------------------------

  int get currentIndex => _current;
  TrackerPattern get current => patterns[_current];
  int get channelCount => _engine.channels.length;
  int get rows => _engine.rows;
  TrackerTiming get timing => _engine.timing;
  List<TrackerChannel> get channels => _engine.channels;

  /// Total song length in ms (uniform pattern length for now — one pattern's
  /// [TrackerTiming.totalMs] per order entry).
  int get songTotalMs => timing.totalMs * order.length;

  /// The ms offset where the order entry at [orderIndex] begins.
  int patternStartMs(int orderIndex) => timing.totalMs * orderIndex;

  /// The order position (index into [order]) sounding at song-time [ms].
  int orderIndexAtMs(int ms) {
    if (order.isEmpty || timing.totalMs <= 0) return 0;
    final i = ms ~/ timing.totalMs;
    return i < 0 ? 0 : (i >= order.length ? order.length - 1 : i);
  }

  bool get isEmpty => patterns.every((p) => !p.hasAnyNote);

  // --- Pattern editing (delegates to the engine on the current pattern) ---

  /// Persist the engine's live cells back into the current pattern snapshot.
  void syncCurrent() {
    final live = _engine.exportCells();
    for (var c = 0; c < live.length && c < current.cells.length; c++) {
      current.cells[c] = live[c];
    }
  }

  /// Save the live pattern, then load [index] into the engine for editing.
  void selectPattern(int index) {
    assert(index >= 0 && index < patterns.length);
    if (index == _current) return;
    syncCurrent();
    _current = index;
    _engine.importCells(current.cells);
  }

  // --- Song arrangement --------------------------------------------------

  /// Appends a pattern (empty, or a clone of the current one) and returns its
  /// index. Does not touch the order list.
  int addPattern({bool cloneCurrent = false, String? name}) {
    syncCurrent();
    final p = cloneCurrent
        ? current.clone(name: name ?? _patternName(patterns.length))
        : TrackerPattern.empty(
            name: name ?? _patternName(patterns.length),
            channels: channelCount,
            rows: rows,
          );
    patterns.add(p);
    return patterns.length - 1;
  }

  /// Removes pattern [index] (keeping at least one), remapping the order list
  /// (dropped entries removed; higher indices shifted down). The engine reloads
  /// a valid current pattern.
  void removePattern(int index) {
    if (patterns.length <= 1) return;
    assert(index >= 0 && index < patterns.length);
    syncCurrent();
    patterns.removeAt(index);
    order.removeWhere((o) => o == index);
    for (var i = 0; i < order.length; i++) {
      if (order[i] > index) order[i]--;
    }
    if (order.isEmpty) order.add(0);
    _current = _current >= patterns.length
        ? patterns.length - 1
        : (_current > index ? _current - 1 : _current);
    _engine.importCells(current.cells);
  }

  /// Appends [patternIndex] to the play order.
  void addToOrder(int patternIndex) {
    assert(patternIndex >= 0 && patternIndex < patterns.length);
    order.add(patternIndex);
  }

  /// Removes the order entry at [position] (keeping at least one).
  void removeFromOrder(int position) {
    if (order.length <= 1) return;
    order.removeAt(position);
  }

  // --- Band editing (endless tracks) -------------------------------------

  /// Adds a channel to the band and an empty column to EVERY pattern, keeping
  /// the channel/pattern shapes consistent. Rebuilds the engine so its caches
  /// and channel-index bookkeeping start clean.
  void addChannel({TrackerInstrument? instrument, double gain = 0.6}) {
    syncCurrent();
    final id = 'track${channelCount + 1}';
    final band = List<TrackerChannel>.of(_engine.channels)
      ..add(
        TrackerChannel(
          id: id,
          instrument: instrument ?? kTrackerInstruments.first.build(),
          gain: gain,
          rows: rows,
        ),
      );
    for (final p in patterns) {
      p.cells.add(
        List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true),
      );
    }
    _rebuild(band, _engine.timing);
    _applyMute(); // a new channel is suppressed if a solo is active
  }

  /// Removes channel [index] from the band and from every pattern (keeping at
  /// least one channel).
  void removeChannel(int index) {
    if (channelCount <= 1) return;
    assert(index >= 0 && index < channelCount);
    syncCurrent();
    final band = List<TrackerChannel>.of(_engine.channels)..removeAt(index);
    for (final p in patterns) {
      p.cells.removeAt(index);
    }
    // Remap the mute/solo index sets around the removed channel.
    _userMuted = _remapAfterRemove(_userMuted, index);
    _soloed = _remapAfterRemove(_soloed, index);
    _rebuild(band, _engine.timing);
    _applyMute();
  }

  /// Re-voices channel [index] (delegates to the engine; caches invalidate).
  void setChannelInstrument(int index, TrackerInstrument instrument) =>
      _engine.setChannelInstrument(index, instrument);

  // --- Mute / solo -------------------------------------------------------

  Set<int> _userMuted = {};
  Set<int> _soloed = {};

  bool isMuted(int channel) => _userMuted.contains(channel);
  bool isSoloed(int channel) => _soloed.contains(channel);

  /// Whether [channel] is heard: not user-muted, and (if any channel is soloed)
  /// itself soloed.
  bool isAudible(int channel) =>
      !_userMuted.contains(channel) &&
      (_soloed.isEmpty || _soloed.contains(channel));

  void toggleMute(int channel) {
    if (!_userMuted.remove(channel)) _userMuted.add(channel);
    _applyMute();
  }

  void toggleSolo(int channel) {
    if (!_soloed.remove(channel)) _soloed.add(channel);
    _applyMute();
  }

  /// Pushes the effective mute (user mute OR solo-suppressed) to every channel.
  void _applyMute() {
    for (var i = 0; i < channelCount; i++) {
      _engine.setChannelMuted(i, !isAudible(i));
    }
  }

  static Set<int> _remapAfterRemove(Set<int> s, int removed) => {
        for (final x in s)
          if (x != removed) (x > removed ? x - 1 : x),
      };

  // --- Timing (endless length) -------------------------------------------

  /// Resizes every pattern to [newRows] steps (truncating or padding with empty
  /// cells) and re-times the engine. This is the direct fix for the Beginner
  /// grid's one-bar ceiling.
  void setRows(int newRows) {
    assert(newRows > 0);
    if (newRows == rows) return;
    syncCurrent();
    for (final p in patterns) {
      for (final col in p.cells) {
        _resizeColumn(col, newRows);
      }
    }
    _rebuild(_engine.channels, _engine.timing.copyWith(rows: newRows));
  }

  /// Sets the tempo (BPM) — re-times the engine, cells unchanged.
  void setTempo(int bpm) {
    if (bpm == timing.tempoBpm || bpm <= 0) return;
    _engine.timing = timing.copyWith(tempoBpm: bpm);
  }

  // --- Audio -------------------------------------------------------------

  /// The current pattern mixed to one loop-ready WAV.
  Uint8List renderCurrentPatternWav() => _engine.renderLoop();

  /// The whole song (the [order] list) rendered to one WAV, patterns back to
  /// back. Side-effect-free (the engine's live pattern is restored).
  Uint8List renderSongWav() {
    syncCurrent();
    return renderSong(_engine, [for (final i in order) patterns[i].cells]);
  }

  /// Total rendered song length in samples (uniform pattern length for now).
  int get songTotalSamples => (songTotalMs * kSampleRate) ~/ 1000;

  // --- internals ---------------------------------------------------------

  void _rebuild(List<TrackerChannel> band, TrackerTiming timing) {
    // The engine constructor asserts every channel's cell count == timing.rows,
    // so normalize the band's live cells before building (importCells below then
    // overwrites them with the current pattern's snapshot).
    for (final ch in band) {
      _resizeColumn(ch.cells, timing.rows);
    }
    _engine = TrackerEngine(channels: band, timing: timing);
    _engine.importCells(current.cells);
  }

  static void _resizeColumn(List<TrackerCell> col, int newRows) {
    if (newRows < col.length) {
      col.removeRange(newRows, col.length);
    } else {
      col.addAll(
        List<TrackerCell>.filled(newRows - col.length, TrackerCell.empty),
      );
    }
  }

  /// Classic pattern names: 00, 01, 02, … (two-digit like tracker order lists).
  static String _patternName(int i) => i.toString().padLeft(2, '0');
}
