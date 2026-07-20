// Sf2Zone volume-envelope generators decode correctly: timecents → seconds
// (2^(tc/1200)) and sustain centibels → linear gain (10^(-cB/200)). These drive
// the resampling voice's DAHDSR so a font's own attack/decay/sustain/release
// play as designed.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('envelope timecents → seconds and sustain cB → gain', () {
    const z = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      attackVolTc: 0, // 2^0 = 1 s
      holdVolTc: -6000, // 2^-5 = 1/32 s
      decayVolTc: 1200, // 2^1 = 2 s
      sustainVolCb: 200, // −20 dB → 0.1
    );
    expect(z.attackVolSec, closeTo(1.0, 1e-9));
    expect(z.holdVolSec, closeTo(1 / 32, 1e-9));
    expect(z.decayVolSec, closeTo(2.0, 1e-9));
    expect(z.releaseVolSec, closeTo(0.0009766, 1e-6));
    expect(z.sustainGain, closeTo(0.1, 1e-9));
  });

  test('the defaults are a full-level gate (unset font behaves like before)',
      () {
    const z = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(z.attackVolSec, lessThan(0.002)); // ~1 ms → instant attack
    expect(z.releaseVolSec, lessThan(0.002));
    expect(z.sustainGain, closeTo(1.0, 1e-9)); // full sustain
    // Default filter = wide open (≈ 20 kHz), Butterworth (no resonance).
    expect(z.filterCutoffHz, closeTo(19912, 60));
    expect(z.filterQ, closeTo(0.707, 0.01));
  });

  test('filter: cutoff cents → Hz and resonance cB → Q', () {
    const z = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      filterFcCents: 7200, // 7200/1200 = 6 → 8.176 · 2^6 = 523.3 Hz
      filterQCb: 120, // 12 dB → resonant (Q > 1)
    );
    expect(z.filterCutoffHz, closeTo(523.3, 1));
    expect(z.filterQ, greaterThan(1.0));
  });

  test('LFO: frequency cents → Hz; depths default to no effect', () {
    const off = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(off.vibLfoHz, closeTo(8.176, 0.01)); // 0 cents → 8.176 Hz
    expect(off.vibLfoToPitchCents, 0); // no vibrato by default
    expect(off.modLfoToVolumeCb, 0); // no tremolo by default

    const vib = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      freqVibLfoCents: 1200, // ×2 → ~16.35 Hz
      vibLfoToPitchCents: 40,
    );
    expect(vib.vibLfoHz, closeTo(16.35, 0.05));
    expect(vib.vibLfoToPitchCents, 40);
  });

  test('zone pan (gen 17) 0.1%→−1..1 + sample L/R type', () {
    const centre = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(centre.pan, 0);
    const left = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      panTenthPct: -500,
    );
    const half = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      panTenthPct: 250,
    );
    expect(left.pan, closeTo(-1.0, 1e-9));
    expect(half.pan, closeTo(0.5, 1e-9));

    final l = Sf2Sample(
      name: 's',
      pcm: Float64List(4),
      sampleRate: 44100,
      originalPitch: 60,
      pitchCorrection: 0,
      loopStart: 0,
      loopEnd: 0,
      sampleType: 4,
    );
    expect(l.isLeft, isTrue);
    expect(l.isRight, isFalse);
  });

  test('exclusive class (gen 57) parses; default 0', () {
    const none = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(none.exclusiveClass, 0);
    const hat = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      exclusiveClass: 1,
    );
    expect(hat.exclusiveClass, 1);
  });

  test('velAttenGain: default concave; a low-amount instrument is flat', () {
    // Default (no modulator) → the SF2 concave curve, amount 960 ≈ (vel)^1.4.
    const def = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(def.velAttenGain(1.0), closeTo(1.0, 1e-9)); // full velocity → full
    expect(def.velAttenGain(0.5), closeTo(0.25, 0.005)); // 0.5^2 (amount 960)
    // A low-amount velocity→attenuation modulator (100 cB) → nearly velocity-
    // flat: a soft note stays loud (a sustained organ, not a percussive kit).
    const flat = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      velAttenMods: [100, 1, 1],
    );
    expect(flat.velAttenGain(0.5), closeTo(0.866, 0.01)); // 0.5^(100/480)
  });

  test('key→vol-env decay (gen 40): a high note rings shorter', () {
    const z = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      decayVolTc: 0, // 2^0 = 1 s decay at the reference key 60
      key2VolEnvDecayTc: 100, // 100 timecents shorter per key above 60
    );
    expect(z.volEnvDecaySec(60), closeTo(1.0, 1e-6));
    // key 72 (+12): decay tc = 0 + 100·(60−72) = −1200 → 2^-1 = 0.5 s.
    expect(z.volEnvDecaySec(72), closeTo(0.5, 1e-6));
    // key 48 (−12): +1200 tc → 2 s (low notes ring longer).
    expect(z.volEnvDecaySec(48), closeTo(2.0, 1e-6));
  });

  test('key→mod-env decay (gens 31/32) + modLfo→filter (gen 10) parse', () {
    const z = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      decayModEnvTc: 0, // 1 s mod-env decay at key 60
      key2ModEnvDecayTc: 100, // shorter per key above 60
      modLfoToFilterCents: 2400, // a filter wah
    );
    expect(z.modEnvDecaySec(60), closeTo(1.0, 1e-6));
    expect(z.modEnvDecaySec(72), closeTo(0.5, 1e-6)); // +12 keys → half
    expect(z.modLfoToFilterCents, 2400);
  });

  test('velFilterCents: default darkens soft notes; a mod opens loud ones', () {
    // No modulators → the SF2 default: full velocity keeps the cutoff, silence
    // drops it 2400 cents (soft notes are duller).
    const plain = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(plain.velFilterCents(1.0), closeTo(0, 1e-9));
    expect(plain.velFilterCents(0.0), closeTo(-2400, 1e-9));
    // A drum-kit-style opening modulator (amount +9000, dir 0 = min→max, linear)
    // does the OPPOSITE: a hard hit opens the cutoff wide (its "click").
    const drum = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      velFilterMods: [9000, 0, 0],
    );
    expect(drum.velFilterCents(1.0), closeTo(9000, 1e-9)); // loud → wide open
    expect(drum.velFilterCents(0.0), closeTo(0, 1e-9)); // soft → base cutoff
  });

  test('sampleModes (gen 54): loop / loop-until-release flags', () {
    const none = Sf2Zone(keyLo: 0, keyHi: 127, sampleIndex: 0, rootKey: 60);
    expect(none.loopEnabled, isFalse);
    const loop = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      sampleModes: 1,
    );
    expect(loop.loopEnabled, isTrue);
    expect(loop.loopUntilRelease, isFalse);
    const untilRel = Sf2Zone(
      keyLo: 0,
      keyHi: 127,
      sampleIndex: 0,
      rootKey: 60,
      sampleModes: 3,
    );
    expect(untilRel.loopEnabled, isTrue);
    expect(untilRel.loopUntilRelease, isTrue);
  });
}
