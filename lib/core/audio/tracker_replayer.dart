// lib/core/audio/tracker_replayer.dart
//
// The tick-based Tracker REPLAYER — the audio engine for the classic MOD
// effect-column PITCH commands (phase 2). Where the offline renderer
// (tracker_engine.dart) renders each note in isolation as a segment, the
// replayer walks order → pattern → row → TICK holding per-channel pitch / volume
// / LFO state across ticks, so effects that need cross-tick continuity —
// portamento, vibrato, tremolo, arpeggio — become possible. It synthesizes each
// additive channel with a PHASE-ACCUMULATING oscillator (`phase += 2π·f/sr` per
// sample, exactly like [renderNoteWithEffect]) so a time-varying frequency stays
// phase-continuous.
//
// Commands implemented here (additive voices):
//   0xy arpeggio · 1xx porta up · 2xx porta down · 3xx tone porta ·
//   4xy vibrato · 5xy tone-porta+vol-slide · 6xy vibrato+vol-slide ·
//   7xy tremolo · Axy volume slide (per-tick) · Cxx set volume.
// (9xx sample-offset and the flow commands Bxx/Dxx/Fxx/Exy are later phases; the
// row-timing map below is already emitted so the flow phase can make it
// non-uniform without changing this file's shape.)
//
// Mixing (see Trap A in docs/TRACKER_REPLAYER_HANDOVER.md): the replayer sums
// voices at a FIXED-normalized amplitude (each additive voice divided by its
// timbre's harmonic-sum, so peak ≤ 1) × the channel gain, then a tanh soft-knee —
// it does NOT unit-peak each stem per render. That is the whole point: a Cxx or a
// tremolo changes the summed amplitude audibly, instead of being normalized away.
// This is a deliberate divergence from the offline `mixStems` path, gated to the
// replayer (only songs that `usesCommands`). Non-additive channels (sfxr / sample
// / percussion) fall back to the offline whole-channel render, unit-peaked × gain
// like `mixStems`, so they still sound (their per-note effects are ignored for
// now — documented limitation).
//
// The state machine is exposed pure (no audio) via [traceChannel] for trajectory
// tests — see test/tracker_replayer_test.dart.
//
// Flutter-free → unit-tested without a device.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_replay.dart'
    show kFxVolumeSlide, kFxSetVolume, kDefaultTicksPerRow;
import 'package:comet_beat/core/audio/tracker_song.dart';

// --- Command nibbles ---------------------------------------------------------

const int kFxArpeggio = 0x0; // 0xy (only when the param is non-zero)
const int kFxPortaUp = 0x1; // 1xx
const int kFxPortaDown = 0x2; // 2xx
const int kFxTonePorta = 0x3; // 3xx
const int kFxVibrato = 0x4; // 4xy
const int kFxTonePortaVolSlide = 0x5; // 5xy = 3xx (memory) + Axy
const int kFxVibratoVolSlide = 0x6; // 6xy = 4xy (continue) + Axy
const int kFxTremolo = 0x7; // 7xy

// --- Tuning constants (MUSICAL APPROXIMATIONS, not period-accurate MOD) -------
//
// Real MOD effects operate on Amiga period units; we model pitch in fractional
// semitones, so these map a command's param to a per-tick semitone/volume delta.
// Chosen for a pleasant musical feel; documented so the trajectory tests pin
// them.

/// Semitones per porta param-unit, per tick (1xx/2xx/3xx). 16 units ≈ 1 st/tick.
const double kPortaSemitonesPerUnit = 1 / 16;

/// Vibrato depth: semitones per depth-unit (y). 8 ⇒ ±1 semitone.
const double kVibratoDepthSemitonesPerUnit = 1 / 8;

/// Vibrato phase advance (radians) per speed-unit (x), per tick. A full cycle
/// takes 32/x ticks.
const double kVibratoRadPerSpeedUnit = 2 * pi / 32;

/// Tremolo depth: volume units (0..64) per depth-unit (y).
const double kTremoloDepthPerUnit = 1.0;

/// Tremolo phase advance (radians) per speed-unit (x), per tick.
const double kTremoloRadPerSpeedUnit = 2 * pi / 32;

/// The full channel volume (classic tracker 0..64).
const int kMaxVolume = 64;

// --- Row-timing map ----------------------------------------------------------

/// One entry of the replayer's timing map: the wall-clock onset of a played row,
/// with the order/pattern/row it corresponds to. Under flow commands (phase 3)
/// the cadence and order become non-uniform; the Advanced screen's playhead reads
/// this instead of assuming fixed pattern lengths.
class RowTiming {
  const RowTiming(this.startMs, this.orderIndex, this.patternIndex, this.row);

  final int startMs;
  final int orderIndex;
  final int patternIndex;
  final int row;

  @override
  String toString() =>
      'RowTiming($startMs ms, order $orderIndex, pat $patternIndex, row $row)';
}

/// The result of a replay: the mixed PCM16 and the row-timing map.
class ReplayResult {
  const ReplayResult(this.pcm, this.timing);

  final Int16List pcm;
  final List<RowTiming> timing;
}

// --- The per-channel voice state machine -------------------------------------

/// Mutable per-channel replay state, advanced tick by tick. Public fields are the
/// trajectory the tests assert against.
class ReplayVoice {
  /// Current base pitch as a FRACTIONAL MIDI note (porta/tone-porta move this).
  double pitch = 0;

  /// Tone-porta (3xx/5xy) target pitch — the row's note.
  double targetPitch = 0;

  /// Channel volume, 0..64 (persists across rows).
  int volume = kMaxVolume;

  /// The soft/ghost-note multiplier (TrackerCell.volume, 0..1) of the CURRENT
  /// note — applied on top of [volume] in synthesis.
  double noteVolume = 1.0;

  /// Whether a note has ever been triggered (so 3xx with no prior note starts).
  bool active = false;

  // Effect memory: a 0 param reuses the last non-zero param for that command.
  int _memPortaUp = 0;
  int _memPortaDown = 0;
  int _memTonePorta = 0;
  int _memVibSpeed = 0;
  int _memVibDepth = 0;
  int _memTremSpeed = 0;
  int _memTremDepth = 0;
  int _memVolSlide = 0;

  // LFO phases (radians), reset on a new note.
  double _vibPhase = 0;
  double _tremPhase = 0;

  // The command armed for the current row.
  int _cmd = 0;
  int _param = 0;
  bool _retriggered = false; // did the current row (re)trigger a note?

  // Audio-only envelope bookkeeping (ignored by [traceChannel]).
  int noteStartSample = 0;
  double noteSeconds = 1.0;
  double oscPhase = 0;

  bool get _isTonePorta => _cmd == kFxTonePorta || _cmd == kFxTonePortaVolSlide;
  bool get _isVibrato => _cmd == kFxVibrato || _cmd == kFxVibratoVolSlide;
  bool get _isVolSlide =>
      _cmd == kFxVolumeSlide ||
      _cmd == kFxTonePortaVolSlide ||
      _cmd == kFxVibratoVolSlide;
  bool get _isArpeggio => _cmd == kFxArpeggio && _param != 0;

  /// Whether [cell] would (re)trigger the note — a pitched cell that is NOT a
  /// tone-porta continuation.
  static bool triggers(TrackerCell cell) =>
      cell.midi != null &&
      cell.fxCmd != kFxTonePorta &&
      cell.fxCmd != kFxTonePortaVolSlide;

  /// Arm the row: parse the cell, (re)trigger the note if pitched, set the target
  /// for tone-porta, load the volume for Cxx, and fill effect memory. Call once
  /// at tick 0.
  void armRow(TrackerCell cell) {
    _cmd = cell.fxCmd;
    _param = cell.fxParam;
    _retriggered = false;

    if (cell.midi != null) {
      final m = cell.midi!.toDouble();
      if (_isTonePorta) {
        targetPitch = m;
        if (!active) {
          pitch = m;
          active = true;
          _retriggered = true;
          noteVolume = cell.volume ?? 1.0;
          _vibPhase = 0;
          _tremPhase = 0;
        }
      } else {
        pitch = m;
        targetPitch = m;
        active = true;
        _retriggered = true;
        noteVolume = cell.volume ?? 1.0;
        _vibPhase = 0;
        _tremPhase = 0;
      }
    }

    // Effect memory + immediate (tick-0) commands.
    switch (_cmd) {
      case kFxPortaUp:
        if (_param != 0) _memPortaUp = _param;
      case kFxPortaDown:
        if (_param != 0) _memPortaDown = _param;
      case kFxTonePorta:
        if (_param != 0) _memTonePorta = _param;
      case kFxVibrato:
      case kFxVibratoVolSlide:
        final x = (_param >> 4) & 0xF, y = _param & 0xF;
        if (x != 0) _memVibSpeed = x;
        if (y != 0) _memVibDepth = y;
        if (_cmd == kFxVibratoVolSlide && _param != 0) _memVolSlide = _param;
      case kFxTremolo:
        final x = (_param >> 4) & 0xF, y = _param & 0xF;
        if (x != 0) _memTremSpeed = x;
        if (y != 0) _memTremDepth = y;
      case kFxTonePortaVolSlide:
        if (_param != 0) _memVolSlide = _param;
      case kFxVolumeSlide:
        if (_param != 0) _memVolSlide = _param;
      case kFxSetVolume:
        volume = _param.clamp(0, kMaxVolume);
    }
  }

  /// True on any row that (re)triggered a note (so the audio renderer can reset
  /// the envelope). Valid after [armRow].
  bool get retriggeredThisRow => _retriggered;

  /// Advance one tick [k] (0-based within the row) and return the effective
  /// (pitch, volume0to64) to synthesize this tick. [ticksPerRow] is the row's
  /// speed. Slide-type effects act on ticks 1.. (tick 0 holds), matching classic
  /// tracker behaviour; arpeggio and the LFOs act on every tick.
  ({double pitch, double volume}) tick(int k, int ticksPerRow) {
    var effPitch = pitch;
    var effVol = volume.toDouble();

    // Arpeggio: cycle base / base+x / base+y each tick (does not move `pitch`).
    if (_isArpeggio) {
      final x = (_param >> 4) & 0xF, y = _param & 0xF;
      final steps = [0, x, y];
      effPitch = pitch + steps[k % 3].toDouble();
    }

    // Porta up / down: move `pitch` on ticks > 0.
    if (_cmd == kFxPortaUp && k > 0) {
      pitch += _memPortaUp * kPortaSemitonesPerUnit;
      effPitch = pitch;
    } else if (_cmd == kFxPortaDown && k > 0) {
      pitch -= _memPortaDown * kPortaSemitonesPerUnit;
      effPitch = pitch;
    }

    // Tone porta: slide toward the target, never overshoot.
    if (_isTonePorta && k > 0) {
      final step = _memTonePorta * kPortaSemitonesPerUnit;
      if (pitch < targetPitch) {
        pitch = min(targetPitch, pitch + step);
      } else if (pitch > targetPitch) {
        pitch = max(targetPitch, pitch - step);
      }
      effPitch = pitch;
    }

    // Vibrato: zero-mean sine on pitch; phase advances each tick.
    if (_isVibrato) {
      final depth = _memVibDepth * kVibratoDepthSemitonesPerUnit;
      effPitch = pitch + depth * sin(_vibPhase);
      _vibPhase += _memVibSpeed * kVibratoRadPerSpeedUnit;
    }

    // Tremolo: zero-mean sine on volume; phase advances each tick.
    if (_cmd == kFxTremolo) {
      final depth = _memTremDepth * kTremoloDepthPerUnit;
      effVol = (volume + depth * sin(_tremPhase)).clamp(0.0, kMaxVolume + 0.0);
      _tremPhase += _memTremSpeed * kTremoloRadPerSpeedUnit;
    }

    // Volume slide (A / 5 / 6): move `volume` on ticks > 0.
    if (_isVolSlide && k > 0) {
      final x = (_memVolSlide >> 4) & 0xF, y = _memVolSlide & 0xF;
      volume = (volume + x - y).clamp(0, kMaxVolume);
      if (_cmd != kFxTremolo) effVol = volume.toDouble();
    }

    return (pitch: effPitch, volume: effVol);
  }
}

// --- Trajectory trace (pure, for tests) --------------------------------------

/// The per-tick effective (pitch, volume) trajectory of one channel — the pure
/// state-machine output with no audio, for trajectory tests. `pitch[r][k]` is the
/// fractional-MIDI pitch synthesized at row r, tick k; `volume[r][k]` is 0..64.
class ChannelTrace {
  ChannelTrace(this.pitch, this.volume);

  final List<List<double>> pitch;
  final List<List<double>> volume;

  /// The effective pitch at row [r], tick [k].
  double pitchAt(int r, int k) => pitch[r][k];

  /// The effective volume (0..64) at row [r], tick [k].
  double volumeAt(int r, int k) => volume[r][k];
}

/// Runs the voice state machine over [cells] and returns the per-tick
/// (pitch, volume) trajectory — no audio. The correctness anchor for phase 2.
ChannelTrace traceChannel(
  List<TrackerCell> cells, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  final voice = ReplayVoice();
  final pitch = <List<double>>[];
  final volume = <List<double>>[];
  for (final cell in cells) {
    voice.armRow(cell);
    final rowPitch = <double>[];
    final rowVol = <double>[];
    for (var k = 0; k < ticksPerRow; k++) {
      final s = voice.tick(k, ticksPerRow);
      rowPitch.add(s.pitch);
      rowVol.add(s.volume);
    }
    pitch.add(rowPitch);
    volume.add(rowVol);
  }
  return ChannelTrace(pitch, volume);
}

// --- Audio rendering ---------------------------------------------------------

double _freqOfMidi(double midi) => 440.0 * pow(2.0, (midi - 69.0) / 12.0);

double _tanh(double x) {
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

/// The row after [from] (exclusive) in [cells] that (re)triggers a note, or
/// `cells.length` if none — the end of the current note's run (for the envelope).
int _nextTriggerRow(List<TrackerCell> cells, int from) {
  for (var r = from + 1; r < cells.length; r++) {
    if (ReplayVoice.triggers(cells[r])) return r;
  }
  return cells.length;
}

/// Whether [instrument] is an additive voice the replayer synthesizes tick-wise.
Instrument? _additiveOf(TrackerInstrument instrument) =>
    instrument is AdditiveInstrument ? instrument.instrument : null;

/// Renders one channel's [cells] into [mix] starting at [sampleOffset]. Additive
/// voices synthesize per tick (honouring commands); other instruments fall back
/// to the offline whole-channel render (unit-peak × gain), so they still sound.
void _renderChannelInto(
  Float64List mix,
  TrackerChannel channel,
  List<TrackerCell> cells,
  TrackerTiming timing,
  int ticksPerRow,
  int sampleOffset,
) {
  if (channel.muted || !cells.any((c) => !c.isEmpty)) return;

  final inst = _additiveOf(channel.instrument);
  if (inst == null) {
    // Non-additive: offline render, unit-peak, × gain, summed at true amplitude.
    final stem = channel.instrument.renderChannel(cells, timing);
    var peak = 0.0;
    for (final v in stem) {
      if (v.abs() > peak) peak = v.abs();
    }
    if (peak == 0) return;
    final scale = channel.gain / peak;
    final n = min(stem.length, mix.length - sampleOffset);
    for (var i = 0; i < n; i++) {
      mix[sampleOffset + i] += stem[i] * scale;
    }
    return;
  }

  final timbre = timbreFor(inst);
  final harmonics = timbre.harmonics;
  final attackSec = timbre.attackMs / 1000;
  final decay = timbre.decay;
  var harmNorm = 0.0;
  for (final h in harmonics) {
    harmNorm += h.abs();
  }
  if (harmNorm == 0) harmNorm = 1;
  final gain = channel.gain;

  final voice = ReplayVoice();
  final rows = cells.length;
  for (var r = 0; r < rows; r++) {
    voice.armRow(cells[r]);
    if (voice.retriggeredThisRow) {
      voice.oscPhase = 0;
      voice.noteStartSample = sampleOffset + timing.stepStartSample(r);
      final runEnd = _nextTriggerRow(cells, r);
      final endSample =
          runEnd < rows ? timing.stepStartSample(runEnd) : timing.totalSamples;
      final runSamples = endSample - timing.stepStartSample(r);
      voice.noteSeconds = runSamples > 0 ? runSamples / kSampleRate : 0.001;
    }
    if (!voice.active) continue;

    final rowStart = sampleOffset + timing.stepStartSample(r);
    final rowEnd = sampleOffset +
        (r + 1 < rows ? timing.stepStartSample(r + 1) : timing.totalSamples);
    for (var k = 0; k < ticksPerRow; k++) {
      final ts = rowStart + ((rowEnd - rowStart) * k) ~/ ticksPerRow;
      final te = rowStart + ((rowEnd - rowStart) * (k + 1)) ~/ ticksPerRow;
      final state = voice.tick(k, ticksPerRow);
      final freq = _freqOfMidi(state.pitch);
      final volScale = (state.volume / kMaxVolume) * voice.noteVolume * gain;
      final phaseInc = 2 * pi * freq / kSampleRate;
      for (var i = ts; i < te && i < mix.length; i++) {
        final t = (i - voice.noteStartSample) / kSampleRate;
        if (t < 0) continue;
        final attack = t < attackSec ? t / attackSec : 1.0;
        final env = attack * exp(-decay * t / voice.noteSeconds);
        var sample = 0.0;
        for (var h = 0; h < harmonics.length; h++) {
          sample += harmonics[h] * sin(voice.oscPhase * (h + 1));
        }
        mix[i] += (sample / harmNorm) * env * volScale;
        voice.oscPhase += phaseInc;
      }
    }
  }
}

/// Converts a Float64 mix to PCM16 with the same tanh soft-knee as [mixStems].
Int16List _mixToPcm(Float64List mix) {
  final out = Int16List(mix.length);
  for (var i = 0; i < mix.length; i++) {
    out[i] = (_tanh(mix[i]) * 0.95 * 32767).round();
  }
  return out;
}

/// Replays a single pattern ([cells] per channel of [channels]) at [timing],
/// returning the mixed PCM16. Used for the current-pattern preview.
ReplayResult replayPattern(
  List<TrackerChannel> channels,
  List<List<TrackerCell>> cells,
  TrackerTiming timing, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  final mix = Float64List(timing.totalSamples);
  for (var c = 0; c < channels.length && c < cells.length; c++) {
    _renderChannelInto(mix, channels[c], cells[c], timing, ticksPerRow, 0);
  }
  return ReplayResult(_mixToPcm(mix), const [RowTiming(0, 0, 0, 0)]);
}

/// Replays the whole [song] (its order list) into one mixed PCM16 + a row-timing
/// map. Timing is uniform for now (one [TrackerTiming.totalMs] per order entry);
/// the flow phase makes it non-uniform. Side-effect-free.
ReplayResult replaySong(
  TrackerSong song, {
  int ticksPerRow = kDefaultTicksPerRow,
}) {
  song.syncCurrent();
  final timing = song.timing;
  final channels = song.channels;
  final order = song.order;
  final patternSamples = timing.totalSamples;
  final mix = Float64List(patternSamples * order.length);
  final timingMap = <RowTiming>[];

  for (var o = 0; o < order.length; o++) {
    final patternIndex = order[o];
    final cells = song.patterns[patternIndex].cells;
    final sampleOffset = patternSamples * o;
    final baseMs = timing.totalMs * o;
    for (var r = 0; r < timing.rows; r++) {
      timingMap.add(
        RowTiming(baseMs + timing.stepOnsetMs(r).round(), o, patternIndex, r),
      );
    }
    for (var c = 0; c < channels.length && c < cells.length; c++) {
      _renderChannelInto(
        mix,
        channels[c],
        cells[c],
        timing,
        ticksPerRow,
        sampleOffset,
      );
    }
  }
  return ReplayResult(_mixToPcm(mix), timingMap);
}
