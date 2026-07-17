// lib/core/audio/crisp_dsp/voice_fx.dart
//
// Kid voice effects for the Tracker's record-your-voice instrument. Each takes a
// recorded sample and returns a transformed one that is still usable as an
// in-tune sampled instrument — so the effects are PITCH- AND LENGTH-PRESERVING
// (timbral only): chipmunk/monster/deep via [formantShift] (change vocal-tract
// character, not pitch), robot via ring-modulation + bit-crush. This keeps the
// sample's base pitch fixed, so a channel's notes still land where the grid says.
//
// (A pitch-changing "high/low voice" mode can use granularPitchShift from
// pitch_shift.dart, but then the instrument's baseMidi must move with it — out of
// scope for the in-tune presets here.)

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/distortion.dart';
import 'package:comet_beat/core/audio/crisp_dsp/formant_shift.dart';
import 'package:comet_beat/core/audio/crisp_dsp/ring_mod.dart';
import 'package:comet_beat/core/audio/synth.dart' show kSampleRate;

/// The voice-transform palette offered when recording an instrument. All presets
/// are pitch- AND length-preserving (timbral only), so a recorded sample stays in
/// tune as a channel instrument.
enum VoiceEffect {
  normal,
  chipmunk,
  monster,
  deep,
  robot,
  alien,
  cyborg,
  radio,
  demon,
}

/// Applies [fx] to [sample], returning a new (pitch/length-preserving) buffer.
Float64List applyVoiceEffect(
  Float64List sample,
  VoiceEffect fx, {
  int sampleRate = kSampleRate,
}) {
  switch (fx) {
    case VoiceEffect.normal:
      return Float64List.fromList(sample);
    case VoiceEffect.chipmunk:
      return formantShift(sample, 0.5);
    case VoiceEffect.monster:
      return formantShift(sample, -0.5);
    case VoiceEffect.deep:
      return formantShift(sample, -0.3);
    case VoiceEffect.robot:
      return _robot(sample, sampleRate);
    case VoiceEffect.alien:
      // Bright, shimmery: formant up + a mid ring-mod carrier.
      return ringModFx(
        formantShift(sample, 0.4),
        carrierHz: 150,
        mix: 0.6,
        sampleRate: sampleRate,
      );
    case VoiceEffect.cyborg:
      // Robotic + gritty: low ring-mod, then soft-clip crunch.
      return distortionFx(
        ringModFx(sample, carrierHz: 80, mix: 0.5, sampleRate: sampleRate),
        drive: 3,
        mix: 0.6,
      );
    case VoiceEffect.radio:
      // Telephone/AM: band-limit, then a touch of grit.
      return distortionFx(
        _bandpass(sample, sampleRate, 500, 2500),
        drive: 2,
        mix: 0.3,
      );
    case VoiceEffect.demon:
      // Deep + fuzzy growl: formant down, then a fuzz shaper.
      return distortionFx(
        formantShift(sample, -0.5),
        kind: DistortionKind.fuzz,
        drive: 2,
        mix: 0.5,
      );
  }
}

/// A cheap band-pass ([lowHz]..[highHz]) — a 1-pole high-pass into a 1-pole
/// low-pass. Length-preserving. Used for the "radio" voice.
Float64List _bandpass(
  Float64List s,
  int sampleRate,
  double lowHz,
  double highHz,
) {
  final out = Float64List(s.length);
  final aHp = 1 - exp(-2 * pi * lowHz / sampleRate);
  final aLp = 1 - exp(-2 * pi * highHz / sampleRate);
  var hpState = 0.0, lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    hpState += aHp * (s[i] - hpState); // low-passed copy…
    final hp = s[i] - hpState; // …subtracted = high-pass
    lp += aLp * (hp - lp); // then low-pass → band-pass
    out[i] = lp;
  }
  return out;
}

/// Robot voice: ring-modulation (a metallic carrier) + bit-crush grit. Both are
/// pitch- and length-preserving.
Float64List _robot(Float64List s, int sampleRate) {
  final out = Float64List(s.length);
  const carrierHz = 60.0;
  const bits = 6;
  final levels = pow(2, bits).toDouble();
  for (var i = 0; i < s.length; i++) {
    final t = i / sampleRate;
    var v = s[i] * sin(2 * pi * carrierHz * t); // ring mod
    v = (v * levels).floorToDouble() / levels; // bit crush
    out[i] = v;
  }
  return out;
}
