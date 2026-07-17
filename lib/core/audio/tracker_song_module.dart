// lib/core/audio/tracker_song_module.dart
//
// Imports a real tracker MODULE (.mod / .s3m / .xm / .it) into an Advanced
// Tracker [TrackerSong]: every pattern, every channel, the order list, and a
// per-channel SAMPLE instrument taken from the module's own samples. Built on
// the existing readers (parseAnyModule -> ModuleDoc) and the sample bridge
// (sampleInstrumentFromDoc), so nothing about the codecs is re-implemented here.
//
// Two lossy adaptations (documented, unavoidable given the Advanced model):
//   * Per-CELL instrument columns collapse to ONE instrument per channel — we
//     pick the sample each channel plays most often. (A channel that swaps
//     samples mid-pattern keeps its notes but plays them with its dominant
//     sample.)
//   * The model uses a uniform row count across patterns, so every pattern is
//     fitted to the module's most common pattern length (MOD/S3M are all 64
//     rows -> lossless; XM/IT with mixed lengths are padded/truncated).
//
// Flutter-free -> unit-tested in test/tracker_song_module_test.dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart'
    show parseAnyModule;
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:comet_beat/core/audio/mod/module_instrument_bridge.dart'
    show sampleInstrumentFromDoc;
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';

/// Parses raw module [bytes] and imports them (throws the reader's
/// FormatException on malformed input, so callers can show a friendly error).
TrackerSong songFromModuleBytes(Uint8List bytes) =>
    songFromModuleDoc(parseAnyModule(bytes));

/// Imports an already-parsed [ModuleDoc].
TrackerSong songFromModuleDoc(ModuleDoc doc) {
  final channelCount = doc.channelCount < 1 ? 1 : doc.channelCount;
  final rows = _modalRows(doc.patterns);
  final rep = _repInstrumentPerChannel(doc, channelCount);

  final band = <TrackerChannel>[
    for (var c = 0; c < channelCount; c++)
      TrackerChannel(
        id: 'ch${c + 1}',
        instrument: _instrumentForChannel(doc, rep[c], c),
        rows: rows,
      ),
  ];

  final timing = TrackerTiming(
    tempoBpm: doc.initialTempo.clamp(32, 255),
    rows: rows,
  );

  final patterns = <TrackerPattern>[
    for (var pi = 0; pi < doc.patterns.length; pi++)
      _patternFromDoc(doc.patterns[pi], channelCount, rows, pi),
  ];

  final order = [
    for (final o in doc.order)
      if (o >= 0 && o < patterns.length) o,
  ];

  return TrackerSong.fromParts(
    channels: band,
    timing: timing,
    patterns: patterns,
    order: order,
  );
}

/// The most common pattern row count (falls back to 64 — the MOD/S3M default).
int _modalRows(List<DocPattern> patterns) {
  if (patterns.isEmpty) return 64;
  final counts = <int, int>{};
  for (final p in patterns) {
    final n = p.numRows;
    if (n > 0) counts[n] = (counts[n] ?? 0) + 1;
  }
  if (counts.isEmpty) return 64;
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// For each channel, the 1-based sample index it triggers most often (0 = none).
List<int> _repInstrumentPerChannel(ModuleDoc doc, int channelCount) {
  final counts = List.generate(channelCount, (_) => <int, int>{});
  for (final p in doc.patterns) {
    for (var r = 0; r < p.numRows; r++) {
      final row = p.rows[r];
      for (var c = 0; c < channelCount && c < row.length; c++) {
        final ins = row[c].instrument;
        if (ins > 0) counts[c][ins] = (counts[c][ins] ?? 0) + 1;
      }
    }
  }
  return [
    for (var c = 0; c < channelCount; c++)
      counts[c].isEmpty
          ? 0
          : counts[c].entries.reduce((a, b) => a.value >= b.value ? a : b).key,
  ];
}

/// A channel's instrument: its dominant module sample, else a rotating additive
/// voice so empty channels still sound distinct.
TrackerInstrument _instrumentForChannel(ModuleDoc doc, int ins, int c) {
  if (ins >= 1 && ins - 1 < doc.samples.length) {
    final sample = doc.samples[ins - 1];
    if (!sample.isEmpty) {
      return sampleInstrumentFromDoc('smp$ins', sample);
    }
  }
  const voices = [
    Instrument.piano,
    Instrument.cello,
    Instrument.flute,
    Instrument.musicBox,
  ];
  return AdditiveInstrument('ch${c + 1}', voices[c % voices.length]);
}

/// Transposes a row-major [DocPattern] into a channel-major [TrackerPattern],
/// fitting it to [rows] (extra rows dropped; short patterns padded with empties).
TrackerPattern _patternFromDoc(
  DocPattern dp,
  int channelCount,
  int rows,
  int index,
) {
  final cells = <List<TrackerCell>>[
    for (var c = 0; c < channelCount; c++)
      List<TrackerCell>.filled(rows, TrackerCell.empty, growable: true),
  ];
  for (var r = 0; r < dp.numRows && r < rows; r++) {
    final row = dp.rows[r];
    for (var c = 0; c < channelCount && c < row.length; c++) {
      final dc = row[c];
      if (dc.note >= 0) {
        cells[c][r] = TrackerCell(
          midi: dc.note,
          volume: dc.volume >= 0 && dc.volume < 64
              ? (dc.volume / 64).clamp(0.0, 1.0)
              : null,
        );
      }
      // noteOff cells stop a ring in real trackers; our model rings until the
      // next trigger, so a key-off simply leaves the cell empty.
    }
  }
  return TrackerPattern(name: index.toString().padLeft(2, '0'), cells: cells);
}
