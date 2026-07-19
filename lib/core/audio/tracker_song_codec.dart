// TrackerSong (de)serialization — a LOSSLESS native save/load/share format for a
// whole Advanced-Tracker song. Unlike module export (8-bit, effect gaps) or the
// MusicXML-via-Score path (no effects / per-cell instruments), this preserves the
// EXACT document: every pattern cell (note/volume/effect/fxCmd/fxParam/per-cell
// instrument), each channel (instrument, gain, pan, mute, volume/pan envelopes,
// insert effects), the order list, timing, and the shared instrument pool.
//
// Instruments serialize via tracker_instrument_codec, so a song using a loaded
// SoundFont voice (Sf2/MultiSample — not embeddable) throws its
// InstrumentCodecException; use the reference-based store for those. Correctness
// is guaranteed by a render-roundtrip test (a song and its decoded twin render
// byte-identically). Pure Dart, no Flutter. The JSON string is a share token.

import 'dart:convert';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';

/// The on-disk format tag + version (bump on a breaking layout change).
const String kTrackerSongFormat = 'cometbeat.trackersong';
const int kTrackerSongVersion = 1;

/// Serialize a whole [song] to a JSON-safe map (see [trackerSongToJsonString]).
Map<String, dynamic> trackerSongToJson(TrackerSong song) {
  song.syncCurrent(); // fold any live edit into the current pattern first
  return {
    'format': kTrackerSongFormat,
    'version': kTrackerSongVersion,
    'timing': _timingToJson(song.timing),
    'order': List<int>.of(song.order),
    'instruments': [for (final i in song.instruments) instrumentToJson(i)],
    'channels': [for (final c in song.channels) _channelToJson(c)],
    'patterns': [for (final p in song.patterns) _patternToJson(p)],
  };
}

/// Rebuild a [TrackerSong] from [json] (as produced by [trackerSongToJson]).
TrackerSong trackerSongFromJson(Map<String, dynamic> json) {
  final timing = _timingFromJson(json['timing'] as Map<String, dynamic>);
  final patterns = [
    for (final p in (json['patterns'] as List))
      _patternFromJson(p as Map<String, dynamic>),
  ];
  // The engine's channels start on pattern 0; size them to it (fromParts loads
  // pattern 0's cells into the engine).
  final rows0 = patterns.isNotEmpty && patterns.first.cells.isNotEmpty
      ? patterns.first.cells.first.length
      : timing.rows;
  final channels = [
    for (final c in (json['channels'] as List))
      _channelFromJson(c as Map<String, dynamic>, rows0),
  ];
  final instruments = [
    for (final i in (json['instruments'] as List))
      instrumentFromJson(i as Map<String, dynamic>),
  ];
  return TrackerSong.fromParts(
    channels: channels,
    timing: timing,
    patterns: patterns,
    order: [for (final o in (json['order'] as List)) o as int],
    instruments: instruments,
  );
}

/// Convenience: song → compact JSON string (a share token) and back.
String trackerSongToJsonString(TrackerSong song) =>
    jsonEncode(trackerSongToJson(song));

TrackerSong trackerSongFromJsonString(String s) =>
    trackerSongFromJson(jsonDecode(s) as Map<String, dynamic>);

// ── timing ───────────────────────────────────────────────────────────────────

Map<String, dynamic> _timingToJson(TrackerTiming t) => {
      'tempoBpm': t.tempoBpm,
      'rows': t.rows,
      'stepsPerBeat': t.stepsPerBeat,
      'swing': t.swing,
    };

TrackerTiming _timingFromJson(Map<String, dynamic> m) => TrackerTiming(
      tempoBpm: (m['tempoBpm'] as num?)?.toInt() ?? 120,
      rows: (m['rows'] as num?)?.toInt() ?? 16,
      stepsPerBeat: (m['stepsPerBeat'] as num?)?.toInt() ?? 4,
      swing: (m['swing'] as num?)?.toDouble() ?? 0.0,
    );

// ── channel ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _channelToJson(TrackerChannel c) => {
      'id': c.id,
      'instrument': instrumentToJson(c.instrument),
      'gain': c.gain,
      'pan': c.pan,
      'muted': c.muted,
      if (c.volumeEnvelope != null)
        'volumeEnvelope': _volEnvToJson(c.volumeEnvelope!),
      if (c.panEnvelope != null) 'panEnvelope': _panEnvToJson(c.panEnvelope!),
      'effects': [for (final e in c.effects) e.name],
    };

TrackerChannel _channelFromJson(Map<String, dynamic> m, int rows) {
  final ch = TrackerChannel(
    id: (m['id'] as String?) ?? 'ch',
    instrument: instrumentFromJson(m['instrument'] as Map<String, dynamic>),
    rows: rows,
    gain: (m['gain'] as num?)?.toDouble() ?? 0.6,
    pan: (m['pan'] as num?)?.toDouble() ?? 0.0,
    volumeEnvelope: m['volumeEnvelope'] == null
        ? null
        : _volEnvFromJson(m['volumeEnvelope'] as Map<String, dynamic>),
    panEnvelope: m['panEnvelope'] == null
        ? null
        : _panEnvFromJson(m['panEnvelope'] as Map<String, dynamic>),
    effects: [
      for (final e in (m['effects'] as List? ?? const []))
        TrackerChannelEffect.values.byName(e as String),
    ],
  );
  ch.muted = (m['muted'] as bool?) ?? false;
  return ch;
}

// ── envelopes ────────────────────────────────────────────────────────────────

Map<String, dynamic> _volEnvToJson(VolumeEnvelope e) => {
      'points': [
        for (final p in e.points) {'ms': p.ms, 'level': p.level},
      ],
    };

VolumeEnvelope _volEnvFromJson(Map<String, dynamic> m) => VolumeEnvelope([
      for (final p in (m['points'] as List))
        (
          ms: ((p as Map)['ms'] as num).toInt(),
          level: (p['level'] as num).toDouble(),
        ),
    ]);

Map<String, dynamic> _panEnvToJson(PanEnvelope e) => {
      'points': [
        for (final p in e.points) {'ms': p.ms, 'pan': p.pan},
      ],
    };

PanEnvelope _panEnvFromJson(Map<String, dynamic> m) => PanEnvelope([
      for (final p in (m['points'] as List))
        (
          ms: ((p as Map)['ms'] as num).toInt(),
          pan: (p['pan'] as num).toDouble(),
        ),
    ]);

// ── pattern + cells ──────────────────────────────────────────────────────────

Map<String, dynamic> _patternToJson(TrackerPattern p) => {
      'name': p.name,
      // Channel-major, like the model; an empty cell is null (compact).
      'cells': [
        for (final col in p.cells) [for (final cell in col) _cellToJson(cell)],
      ],
    };

TrackerPattern _patternFromJson(Map<String, dynamic> m) => TrackerPattern(
      name: (m['name'] as String?) ?? '00',
      cells: [
        for (final col in (m['cells'] as List))
          [
            for (final cell in (col as List))
              _cellFromJson(cell as Map<String, dynamic>?),
          ],
      ],
    );

/// A cell as a compact map of only its non-default fields, or null when empty.
Map<String, dynamic>? _cellToJson(TrackerCell c) {
  if (c.midi == null &&
      c.volume == null &&
      c.effect == TrackerEffect.none &&
      c.fxCmd == 0 &&
      c.fxParam == 0 &&
      c.instrument == 0) {
    return null;
  }
  return {
    if (c.midi != null) 'n': c.midi,
    if (c.volume != null) 'v': c.volume,
    if (c.effect != TrackerEffect.none) 'e': c.effect.name,
    if (c.fxCmd != 0) 'c': c.fxCmd,
    if (c.fxParam != 0) 'p': c.fxParam,
    if (c.instrument != 0) 'i': c.instrument,
  };
}

TrackerCell _cellFromJson(Map<String, dynamic>? m) {
  if (m == null) return TrackerCell.empty;
  return TrackerCell(
    midi: (m['n'] as num?)?.toInt(),
    volume: (m['v'] as num?)?.toDouble(),
    effect: m['e'] == null
        ? TrackerEffect.none
        : TrackerEffect.values.byName(m['e'] as String),
    fxCmd: (m['c'] as num?)?.toInt() ?? 0,
    fxParam: (m['p'] as num?)?.toInt() ?? 0,
    instrument: (m['i'] as num?)?.toInt() ?? 0,
  );
}
