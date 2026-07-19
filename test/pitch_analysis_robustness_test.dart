// Robustness of the live mic pitch detector: the Tuner / Play-along / Chord
// listener feed it untrusted frames (silence, DC, clipping, or NaN/Inf from a
// bad plugin frame). It must never throw and never emit a non-finite reading
// field — a NaN rms would poison downstream onset detection.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void _finite(PitchReading r) {
  expect(r.frequency.isFinite, isTrue, reason: 'frequency ${r.frequency}');
  expect(r.clarity.isFinite, isTrue, reason: 'clarity ${r.clarity}');
  expect(r.rms.isFinite, isTrue, reason: 'rms ${r.rms}');
  expect(r.zcr.isFinite, isTrue, reason: 'zcr ${r.zcr}');
  if (!r.hasPitch) expect(r.nearestMidi, -1);
}

Float64List _fill(int n, double v) => Float64List(n)..fillRange(0, n, v);

Float64List _sine(int n, double freq, {int sr = 44100, double amp = 0.5}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * sin(2 * pi * freq * i / sr);
  }
  return out;
}

void main() {
  final det = PitchDetector();
  final w = det.windowSize;

  group('degenerate frames yield a clean, finite silent reading', () {
    test('empty and tiny windows never throw', () {
      for (final len in [0, 1, 2, 3, 5, 16]) {
        final r = det.analyze(Float64List(len));
        _finite(r);
        expect(r.hasPitch, isFalse);
      }
    });

    test('silence, DC offset and a constant are silent + finite', () {
      for (final v in [0.0, 0.5, -0.9, 1.0]) {
        _finite(det.analyze(_fill(w, v)));
        expect(det.analyze(_fill(w, v)).hasPitch, isFalse);
      }
    });

    test('a hard-clipped square wave stays finite', () {
      final sq = Float64List(w);
      for (var i = 0; i < w; i++) {
        sq[i] = (i ~/ 50).isEven ? 1.0 : -1.0;
      }
      _finite(det.analyze(sq));
    });
  });

  group('NON-FINITE frames must not leak NaN/Inf (the fix)', () {
    test('an all-NaN frame → clean silence with a finite rms', () {
      final r = det.analyze(_fill(w, double.nan));
      _finite(r);
      expect(r.hasPitch, isFalse);
      expect(r.rms, 0.0, reason: 'a garbage frame must read as silence');
    });

    test('a single NaN or Inf sample cannot poison the reading', () {
      for (final bad in [double.nan, double.infinity, -double.infinity]) {
        final buf = _sine(w, 220);
        buf[w ~/ 3] = bad;
        _finite(det.analyze(buf));
      }
    });

    test('an all-Inf frame is finite + silent', () {
      _finite(det.analyze(_fill(w, double.infinity)));
    });
  });

  test('random noise across many seeds never throws and stays finite', () {
    for (var seed = 0; seed < 40; seed++) {
      final r = Random(seed);
      final buf = Float64List(w);
      for (var i = 0; i < w; i++) {
        buf[i] = r.nextDouble() * 2 - 1;
      }
      _finite(det.analyze(buf));
    }
  });

  test('a clean tone still detects correctly (the guard did not break it)', () {
    final r = det.analyze(_sine(w, 220)); // A3
    expect(r.hasPitch, isTrue);
    expect(r.nearestMidi, 57); // A3
    _finite(r);
  });

  test('the streaming analyzer survives NaN chunks mid-stream', () {
    final analyzer = StreamingAudioAnalyzer(detector: PitchDetector());
    // A few seconds of tone with a corrupt (NaN) chunk spliced in.
    final frames = <AnalyzerFrame>[];
    frames.addAll(analyzer.addSamples(_sine(w * 2, 330)));
    frames.addAll(analyzer.addSamples(_fill(w, double.nan)));
    frames.addAll(analyzer.addSamples(_sine(w * 2, 330)));
    expect(frames, isNotEmpty);
    for (final f in frames) {
      _finite(f.pitch);
    }
  });
}
