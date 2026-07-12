// lib/core/audio/synth.dart
//
// Pure-Dart additive synthesizer: renders pitches, chords and sequences to
// 16-bit mono PCM WAV bytes. No assets, no licensing, works on every
// platform (playback happens in AudioService). Piano-ish timbre: a few
// decaying harmonics with a fast attack and exponential decay.

import 'dart:math';
import 'dart:typed_data';

const kSampleRate = 44100;

/// One playable segment: simultaneous frequencies for a duration.
/// A single-element [freqs] is a note; several are a chord.
typedef Segment = ({List<double> freqs, int ms});

double midiToFrequency(int midi) => 440.0 * pow(2.0, (midi - 69) / 12.0);

/// A selectable instrument voice.
enum Instrument { piano, cello, flute, musicBox }

/// A timbre: the relative amplitudes of the harmonics, the attack time, and how
/// fast the note decays over its segment (small = sustained, large = plucked).
class Timbre {
  const Timbre({
    required this.harmonics,
    required this.attackMs,
    required this.decay,
  });

  final List<double> harmonics;
  final double attackMs;
  final double decay;
}

const _timbres = <Instrument, Timbre>{
  // Piano-ish: the original bright, decaying voice.
  Instrument.piano: Timbre(
    harmonics: [1.0, 0.45, 0.22, 0.1, 0.05],
    attackMs: 8,
    decay: 3.0,
  ),
  // Cello: reedy upper harmonics, a slower bow attack, and a sustained tone.
  Instrument.cello: Timbre(
    harmonics: [1.0, 0.6, 0.45, 0.32, 0.22, 0.16, 0.1],
    attackMs: 45,
    decay: 0.9,
  ),
  // Flute: almost pure, soft, sustained.
  Instrument.flute: Timbre(
    harmonics: [1.0, 0.18, 0.06, 0.02],
    attackMs: 35,
    decay: 1.1,
  ),
  // Music box: bright and bell-like, fast decay.
  Instrument.musicBox: Timbre(
    harmonics: [1.0, 0.3, 0.55, 0.2, 0.35, 0.12],
    attackMs: 2,
    decay: 6.0,
  ),
};

/// The timbre for [instrument].
Timbre timbreFor(Instrument instrument) => _timbres[instrument]!;

/// Renders [segments] back-to-back into normalized PCM16 samples.
///
/// [gain] (0..1) scales the final level below the normalized peak — used to
/// voice dynamics (pp..ff) since the output is otherwise peak-normalized.
Int16List renderSegments(
  List<Segment> segments, {
  int sampleRate = kSampleRate,
  Timbre? timbre,
  double gain = 1.0,
}) {
  final voice = timbre ?? _timbres[Instrument.piano]!;
  final harmonics = voice.harmonics;
  final attackSec = voice.attackMs / 1000;
  final decay = voice.decay;
  final totalSamples = segments.fold<int>(
    0,
    (sum, s) => sum + (s.ms * sampleRate) ~/ 1000,
  );
  final buffer = Float64List(totalSamples);

  var offset = 0;
  for (final segment in segments) {
    final n = (segment.ms * sampleRate) ~/ 1000;
    final seconds = segment.ms / 1000;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      // Instrument-specific attack, exponential decay over the segment.
      final attack = t < attackSec ? t / attackSec : 1.0;
      final envelope = attack * exp(-decay * t / seconds);
      var sample = 0.0;
      for (final freq in segment.freqs) {
        for (var h = 0; h < harmonics.length; h++) {
          sample += harmonics[h] * sin(2 * pi * freq * (h + 1) * t);
        }
      }
      buffer[offset + i] = sample * envelope;
    }
    offset += n;
  }

  // Normalize to 80% full scale.
  var peak = 0.0;
  for (final v in buffer) {
    if (v.abs() > peak) peak = v.abs();
  }
  final scale = (peak > 0 ? 0.8 * 32767 / peak : 0.0) * gain.clamp(0.0, 1.0);
  final samples = Int16List(totalSamples);
  for (var i = 0; i < totalSamples; i++) {
    samples[i] = (buffer[i] * scale).round();
  }
  return samples;
}

/// Wraps PCM16 mono samples into a WAV container.
Uint8List wavBytes(Int16List samples, {int sampleRate = kSampleRate}) {
  final dataLength = samples.length * 2;
  final bytes = ByteData(44 + dataLength);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // fmt chunk size
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  writeString(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Convenience: render [segments] straight to WAV bytes.
Uint8List renderWav(
  List<Segment> segments, {
  Timbre? timbre,
  double gain = 1.0,
}) =>
    wavBytes(renderSegments(segments, timbre: timbre, gain: gain));

// --- Retro game SFX (CrispFXR-style: square waves, pitch sweeps) ---
//
// Procedural feedback sounds in the spirit of the maintainer's CrispFXR
// (sfxr-like 8-bit synthesizer): no assets, instantly recognizable.

/// A square-wave segment sweeping from [startFreq] to [endFreq].
Float64List _squareSweep(
  double startFreq,
  double endFreq,
  int ms, {
  int sampleRate = kSampleRate,
}) {
  final n = (ms * sampleRate) ~/ 1000;
  final out = Float64List(n);
  final seconds = ms / 1000;
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final freq = startFreq + (endFreq - startFreq) * (t / seconds);
    phase += freq / sampleRate;
    final attack = t < 0.005 ? t / 0.005 : 1.0;
    final envelope = attack * exp(-2.5 * t / seconds);
    out[i] = (phase % 1.0 < 0.5 ? 1.0 : -1.0) * envelope;
  }
  return out;
}

Uint8List _sfxWav(List<Float64List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final samples = Int16List(total);
  var offset = 0;
  for (final part in parts) {
    for (var i = 0; i < part.length; i++) {
      samples[offset + i] = (part[i] * 0.35 * 32767).round();
    }
    offset += part.length;
  }
  return wavBytes(samples);
}

/// "Correct!" — the classic two-blip pickup coin (B5 → E6).
Uint8List renderSfxCorrect() => _sfxWav([
      _squareSweep(988, 988, 80),
      _squareSweep(1319, 1319, 220),
    ]);

/// "Wrong" — a short, soft descending buzz.
Uint8List renderSfxWrong() => _sfxWav([_squareSweep(220, 150, 250)]);

/// Game finished — an ascending power-up arpeggio with a final sweep.
Uint8List renderSfxFanfare() => _sfxWav([
      _squareSweep(523, 523, 110), // C5
      _squareSweep(659, 659, 110), // E5
      _squareSweep(784, 784, 110), // G5
      _squareSweep(1047, 1319, 450), // C6 sweeping up
    ]);

/// A short metronome tick — a brief high blip, [accent]ed (higher) on the
/// downbeat. Kept high and short to be unobtrusive; it does not need to be
/// mic-safe by itself because the play-along only clicks during the (unscored)
/// count-in (see metronome.dart's CountInClicker).
Uint8List renderSfxTick({bool accent = false}) => _sfxWav([
      _squareSweep(
        accent ? 1760 : 1320,
        accent ? 1760 : 1320,
        accent ? 45 : 32,
      ),
    ]);
