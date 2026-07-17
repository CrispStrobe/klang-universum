// lib/core/audio/tracker_replay.dart
//
// The tracker "replayer" — applies classic MOD-style effect-column commands
// (TrackerCell.fxCmd / fxParam) to a rendered channel stem. This is the audio
// side of the Advanced tracker's effect columns.
//
// Phase 1 covers the VOLUME domain (the most self-contained, and applicable to
// every instrument as a post-multiply on the stem, so it needs no oscillator
// state):
//   * Cxx — set channel volume to xx (0x00–0x40, i.e. 0..64).
//   * Axy — volume slide: raise by x and lower by y each tick over the row.
// Volume PERSISTS across rows (a classic tracker's channel-volume state) and is
// a multiplier on top of the instrument + soft-note level (it does NOT reset on
// a new note in phase 1, so it never clobbers the soft-note dynamics).
//
// Pitch commands (0/1/2/3/4/7 arpeggio/porta/vibrato/tremolo) and flow commands
// (Bxx jump / Dxx break / Fxx speed-tempo) are later phases — the former need
// per-tick oscillator state (a from-scratch additive replayer), the latter a
// playback-flow model above the per-pattern render.
//
// Flutter-free → unit-tested (test/tracker_replay_test.dart).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';

/// MOD effect-command nibbles supported here.
const int kFxVolumeSlide = 0xA; // Axy
const int kFxSetVolume = 0xC; // Cxx

/// The classic default speed (ticks per row) — the slide granularity.
const int kDefaultTicksPerRow = 6;

/// Applies the volume-domain effect column of [cells] to [stem] (a rendered
/// channel buffer), returning a new buffer. A no-op (returns [stem] unchanged)
/// when the channel has no volume commands, so existing patterns pay nothing.
Float64List applyVolumeColumn(
  Float64List stem,
  List<TrackerCell> cells,
  TrackerTiming timing, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  final hasVol = cells.any(
    (c) => c.fxCmd == kFxSetVolume || c.fxCmd == kFxVolumeSlide,
  );
  if (!hasVol) return stem;

  final out = Float64List.fromList(stem);
  final total = timing.totalSamples;
  var level = 1.0; // 0..1 (64 = full)
  for (var r = 0; r < cells.length; r++) {
    final c = cells[r];
    var startLevel = level;
    var endLevel = level;
    if (c.fxCmd == kFxSetVolume) {
      final v = c.fxParam.clamp(0, 64) / 64.0;
      startLevel = v;
      endLevel = v;
      level = v;
    } else if (c.fxCmd == kFxVolumeSlide) {
      final x = (c.fxParam >> 4) & 0xF;
      final y = c.fxParam & 0xF;
      final perTick = (x - y) / 64.0;
      endLevel = (level + perTick * (ticksPerRow - 1)).clamp(0.0, 1.0);
      level = endLevel;
    }
    final s0 = timing.stepStartSample(r);
    final s1 = r + 1 < cells.length ? timing.stepStartSample(r + 1) : total;
    final span = s1 - s0;
    for (var i = s0; i < s1 && i < out.length; i++) {
      final frac = span > 0 ? (i - s0) / span : 0.0;
      out[i] *= startLevel + (endLevel - startLevel) * frac;
    }
  }
  return out;
}
