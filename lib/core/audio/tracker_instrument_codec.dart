// Instrument (de)serialization — the [needs-engine] contract behind a persistent
// sound library / DAW instrument editor: turn any authored [TrackerInstrument]
// into plain JSON and back, so a sound survives across sessions and can be
// shared. Pure Dart, no Flutter.
//
// Covers every instrument a user AUTHORS in the tracker: the procedural voices
// (additive / sfxr / Karplus / FM / subtractive), a recorded [SampleInstrument]
// (its PCM travels as base64 Float32), and [PercussionInstrument]. Loaded
// SoundFont voices ([Sf2Instrument]/[MultiSampleInstrument]) are deliberately
// NOT embedded here — they are megabytes of multi-sample PCM and belong in a
// reference-based store (soundfont file + preset), a documented follow-up.
//
// Correctness is guaranteed by a render-roundtrip test (an instrument and its
// decoded twin render a note identically), so a missed field can't ship.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/crisp_dsp/fm.dart';
import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:comet_beat/core/audio/crisp_dsp/subtractive.dart';
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// Thrown when JSON can't be decoded into an instrument (unknown/missing type).
class InstrumentCodecException implements Exception {
  InstrumentCodecException(this.message);
  final String message;
  @override
  String toString() => 'InstrumentCodecException: $message';
}

/// Whether [instrument] can be serialized by [instrumentToJson]. False for the
/// loaded-SoundFont voices (persist those by file+preset reference instead).
bool isSerializableInstrument(TrackerInstrument instrument) =>
    instrument is AdditiveInstrument ||
    instrument is SfxrInstrument ||
    instrument is KarplusInstrument ||
    instrument is FmInstrument ||
    instrument is SubtractiveInstrument ||
    instrument is SampleInstrument ||
    instrument is PercussionInstrument;

/// Serialize [instrument] to a JSON-safe map. Throws [InstrumentCodecException]
/// for a type that isn't serializable (see [isSerializableInstrument]).
Map<String, dynamic> instrumentToJson(TrackerInstrument instrument) {
  if (instrument is AdditiveInstrument) {
    return {
      'type': 'additive',
      'id': instrument.id,
      'instrument': instrument.instrument.name,
    };
  }
  if (instrument is SfxrInstrument) {
    return {
      'type': 'sfxr',
      'id': instrument.id,
      'seed': instrument.seed,
      'params': _sfxrToJson(instrument.params),
    };
  }
  if (instrument is KarplusInstrument) {
    return {
      'type': 'karplus',
      'id': instrument.id,
      'damping': instrument.damping,
      'blend': instrument.blend,
      'seed': instrument.seed,
    };
  }
  if (instrument is FmInstrument) {
    final p = instrument.preset;
    return {
      'type': 'fm',
      'id': instrument.id,
      'preset': {
        'ratio': p.ratio,
        'index': p.index,
        'indexDecay': p.indexDecay,
        'ampDecay': p.ampDecay,
      },
    };
  }
  if (instrument is SubtractiveInstrument) {
    final p = instrument.preset;
    return {
      'type': 'subtractive',
      'id': instrument.id,
      'preset': {
        'wave': p.wave.name,
        'cutoffStart': p.cutoffStart,
        'cutoffEnd': p.cutoffEnd,
        'cutoffDecay': p.cutoffDecay,
        'ampDecay': p.ampDecay,
      },
    };
  }
  if (instrument is SampleInstrument) {
    return {
      'type': 'sample',
      'id': instrument.id,
      'baseMidi': instrument.baseMidi,
      'loopStart': instrument.loopStart,
      'loopLength': instrument.loopLength,
      'offsetScale': instrument.offsetScale,
      'envelope': _envelopeToJson(instrument.envelope),
      // PCM as base64 Float32 (little-endian) — inaudibly lossy, half the size
      // of Float64 and standard for audio.
      'pcm': _pcmToBase64(instrument.sample),
    };
  }
  if (instrument is PercussionInstrument) {
    return {'type': 'percussion', 'id': instrument.id};
  }
  throw InstrumentCodecException(
    'not serializable: ${instrument.runtimeType} '
    '(loaded SoundFont voices are stored by reference, not embedded)',
  );
}

/// Rebuild a [TrackerInstrument] from [json] (as produced by [instrumentToJson]).
/// Throws [InstrumentCodecException] on an unknown/missing type.
TrackerInstrument instrumentFromJson(Map<String, dynamic> json) {
  final type = json['type'];
  final id = (json['id'] as String?) ?? 'instrument';
  switch (type) {
    case 'additive':
      return AdditiveInstrument(
        id,
        Instrument.values.byName(json['instrument'] as String),
      );
    case 'sfxr':
      return SfxrInstrument(
        id,
        _sfxrFromJson(json['params'] as Map<String, dynamic>),
        seed: (json['seed'] as num?)?.toInt() ?? 0,
      );
    case 'karplus':
      return KarplusInstrument(
        id,
        damping: (json['damping'] as num).toDouble(),
        blend: (json['blend'] as num).toDouble(),
        seed: (json['seed'] as num?)?.toInt() ?? 0,
      );
    case 'fm':
      final p = json['preset'] as Map<String, dynamic>;
      return FmInstrument(
        id,
        FmPreset(
          ratio: (p['ratio'] as num).toDouble(),
          index: (p['index'] as num).toDouble(),
          indexDecay: (p['indexDecay'] as num).toDouble(),
          ampDecay: (p['ampDecay'] as num).toDouble(),
        ),
      );
    case 'subtractive':
      final p = json['preset'] as Map<String, dynamic>;
      return SubtractiveInstrument(
        id,
        SubPreset(
          wave: SubWave.values.byName(p['wave'] as String),
          cutoffStart: (p['cutoffStart'] as num).toDouble(),
          cutoffEnd: (p['cutoffEnd'] as num).toDouble(),
          cutoffDecay: (p['cutoffDecay'] as num).toDouble(),
          ampDecay: (p['ampDecay'] as num).toDouble(),
        ),
      );
    case 'sample':
      return SampleInstrument(
        id,
        _pcmFromBase64(json['pcm'] as String),
        baseMidi: (json['baseMidi'] as num?)?.toInt() ?? 60,
        envelope: _envelopeFromJson(json['envelope'] as Map<String, dynamic>?),
        loopStart: (json['loopStart'] as num?)?.toInt() ?? 0,
        loopLength: (json['loopLength'] as num?)?.toInt() ?? 0,
        offsetScale: (json['offsetScale'] as num?)?.toDouble() ?? 1.0,
      );
    case 'percussion':
      return PercussionInstrument(id);
    default:
      throw InstrumentCodecException('unknown instrument type: $type');
  }
}

/// Convenience: instrument → compact JSON string (e.g. a share token payload).
String instrumentToJsonString(TrackerInstrument instrument) =>
    jsonEncode(instrumentToJson(instrument));

/// Convenience: JSON string → instrument.
TrackerInstrument instrumentFromJsonString(String s) =>
    instrumentFromJson(jsonDecode(s) as Map<String, dynamic>);

// ── helpers ────────────────────────────────────────────────────────────────

Map<String, dynamic> _sfxrToJson(SfxrParams p) => {
      'waveType': p.waveType,
      'noiseType': p.noiseType,
      'attack': p.attack,
      'sustain': p.sustain,
      'punch': p.punch,
      'decay': p.decay,
      'baseFreq': p.baseFreq,
      'freqRamp': p.freqRamp,
      'vibStrength': p.vibStrength,
      'vibSpeed': p.vibSpeed,
      'arpMod': p.arpMod,
      'arpSpeed': p.arpSpeed,
      'duty': p.duty,
      'dutyRamp': p.dutyRamp,
      'repeatSpeed': p.repeatSpeed,
      'lpfFreq': p.lpfFreq,
      'hpfFreq': p.hpfFreq,
      'subBass': p.subBass,
      'distortion': p.distortion,
      'bitCrush': p.bitCrush,
      'soundVol': p.soundVol,
      'fmDepth': p.fmDepth,
      'fmRatio': p.fmRatio,
      'lfoDepth': p.lfoDepth,
      'lfoSpeed': p.lfoSpeed,
    };

double _d(Map<String, dynamic> m, String k, double fallback) =>
    (m[k] as num?)?.toDouble() ?? fallback;

SfxrParams _sfxrFromJson(Map<String, dynamic> m) => SfxrParams(
      waveType: (m['waveType'] as num?)?.toInt() ?? SfxrWave.square,
      noiseType: (m['noiseType'] as num?)?.toInt() ?? 0,
      attack: _d(m, 'attack', 0),
      sustain: _d(m, 'sustain', 0.3),
      punch: _d(m, 'punch', 0),
      decay: _d(m, 'decay', 0.4),
      baseFreq: _d(m, 'baseFreq', 0.3),
      freqRamp: _d(m, 'freqRamp', 0),
      vibStrength: _d(m, 'vibStrength', 0),
      vibSpeed: _d(m, 'vibSpeed', 0),
      arpMod: _d(m, 'arpMod', 0),
      arpSpeed: _d(m, 'arpSpeed', 0),
      duty: _d(m, 'duty', 0),
      dutyRamp: _d(m, 'dutyRamp', 0),
      repeatSpeed: _d(m, 'repeatSpeed', 0),
      lpfFreq: _d(m, 'lpfFreq', 1),
      hpfFreq: _d(m, 'hpfFreq', 0),
      subBass: _d(m, 'subBass', 0),
      distortion: _d(m, 'distortion', 0),
      bitCrush: _d(m, 'bitCrush', 0),
      soundVol: _d(m, 'soundVol', 0.5),
      fmDepth: _d(m, 'fmDepth', 0),
      fmRatio: _d(m, 'fmRatio', 2),
      lfoDepth: _d(m, 'lfoDepth', 0),
      lfoSpeed: _d(m, 'lfoSpeed', 0.2),
    );

Map<String, dynamic> _envelopeToJson(Envelope e) => {
      'attack': e.attack,
      'decay': e.decay,
      'sustain': e.sustain,
      'release': e.release,
      'pitchStart': e.pitchStart,
      'pitchTime': e.pitchTime,
    };

Envelope _envelopeFromJson(Map<String, dynamic>? m) {
  if (m == null) return Envelope.declick;
  return Envelope(
    attack: _d(m, 'attack', 0.004),
    decay: _d(m, 'decay', 0),
    sustain: _d(m, 'sustain', 1),
    release: _d(m, 'release', 0.012),
    pitchStart: _d(m, 'pitchStart', 0),
    pitchTime: _d(m, 'pitchTime', 0.04),
  );
}

String _pcmToBase64(Float64List pcm) {
  final f32 = Float32List.fromList(pcm);
  final bytes = f32.buffer.asUint8List(f32.offsetInBytes, f32.lengthInBytes);
  return base64Encode(bytes);
}

Float64List _pcmFromBase64(String s) {
  final bytes = base64Decode(s);
  // Copy into an aligned buffer (base64Decode's Uint8List may not be
  // 4-byte-aligned for a Float32List view).
  final aligned = Uint8List.fromList(bytes);
  final f32 = aligned.buffer.asFloat32List(0, aligned.lengthInBytes ~/ 4);
  return Float64List.fromList(f32);
}
