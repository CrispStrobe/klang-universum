// test/sfxr_fm_lfo_test.dart
//
// sfxr FM + LFO params: applied only when depth > 0 (so existing presets are
// byte-identical), change the signal when engaged, and stay bounded/deterministic.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/sfxr_fm_lfo_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sfxr.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _gen(SfxrParams p) => sfxrGenerate(p, rng: Random(1));

bool _finite(Float64List b) => b.every((v) => v.isFinite);
double _peak(Float64List b) => b.fold(0.0, (m, v) => max(m, v.abs()));
bool _differs(Float64List a, Float64List b) {
  final n = min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return true;
  }
  return a.length != b.length;
}

void main() {
  const base = SfxrParams(
    waveType: SfxrWave.sine,
    baseFreq: 0.5,
    sustain: 0.2,
    decay: 0.2,
  );
  final dry = _gen(base);

  test('FM (depth 0) leaves the signal unchanged; depth > 0 changes it', () {
    // A non-default fmRatio with fmDepth still 0 must be a no-op (FM off).
    const noFm = SfxrParams(
      waveType: SfxrWave.sine,
      baseFreq: 0.5,
      sustain: 0.2,
      decay: 0.2,
      fmRatio: 5,
    );
    expect(_differs(dry, _gen(noFm)), isFalse);

    const fm = SfxrParams(
      waveType: SfxrWave.sine,
      baseFreq: 0.5,
      sustain: 0.2,
      decay: 0.2,
      fmDepth: 0.5,
      fmRatio: 3,
    );
    final out = _gen(fm);
    expect(_differs(dry, out), isTrue);
    expect(_finite(out), isTrue);
    expect(_peak(out), lessThanOrEqualTo(1.0));
  });

  test('LFO tremolo (depth > 0) modulates the amplitude', () {
    const lfo = SfxrParams(
      waveType: SfxrWave.sine,
      baseFreq: 0.5,
      sustain: 0.2,
      decay: 0.2,
      lfoDepth: 0.6,
      lfoSpeed: 0.5,
    );
    final out = _gen(lfo);
    expect(_differs(dry, out), isTrue);
    expect(_finite(out), isTrue);
    expect(_peak(out), lessThanOrEqualTo(1.0));
  });

  test('FM/LFO output is deterministic for a fixed seed', () {
    const p = SfxrParams(
      waveType: SfxrWave.sine,
      baseFreq: 0.5,
      fmDepth: 0.4,
      lfoDepth: 0.3,
    );
    expect(_differs(_gen(p), _gen(p)), isFalse);
  });

  test('the bell preset (FM + LFO) renders bounded, audible, deterministic',
      () {
    final a = sfxrGenerate(sfxrBell(Random(7)), rng: Random(3));
    final b = sfxrGenerate(sfxrBell(Random(7)), rng: Random(3));
    expect(_peak(a), greaterThan(0.0));
    expect(_peak(a), lessThanOrEqualTo(1.0));
    expect(_finite(a), isTrue);
    expect(_differs(a, b), isFalse); // deterministic
    expect(kSfxrPresets.containsKey('bell'), isTrue);
  });
}
