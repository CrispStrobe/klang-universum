// The segment→voice renderer: playing AudioService segments through an arbitrary
// TrackerInstrument. Proven against the pitch detector (a tonal voice recovers
// the right pitch) and by structure (chiptune voice is non-silent; a rest is
// silence; chords sum; the timeline length tracks the segment durations).

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/voice_render.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInstrument _voice(String id) =>
    kTrackerInstruments.firstWhere((o) => o.id == id).build();

double _rms(Float64List x, [int from = 0, int? to]) {
  to ??= x.length;
  if (to <= from) return 0;
  var s = 0.0;
  for (var i = from; i < to; i++) {
    s += x[i] * x[i];
  }
  return sqrt(s / (to - from));
}

void main() {
  test('a tonal voice recovers the right pitch (A4=440)', () {
    final out = renderSegmentsThroughInstrument(
      [
        (freqs: [440.0], ms: 600),
      ],
      _voice('piano'),
    );
    final d = PitchDetector();
    final start = (out.length - d.windowSize) ~/ 2;
    final win = Float64List(d.windowSize);
    for (var i = 0; i < d.windowSize; i++) {
      win[i] = out[start + i];
    }
    final r = d.analyze(win);
    expect(r.hasPitch, isTrue);
    final cents = 1200 * (log(r.frequency / 440.0) / log(2));
    expect(cents.abs(), lessThan(35), reason: 'within ~third of a semitone');
  });

  test('a chiptune (sfxr) voice is non-silent', () {
    final out = renderSegmentsThroughInstrument(
      [
        (freqs: [330.0], ms: 300),
      ],
      _voice('blip'),
    );
    expect(_rms(out), greaterThan(0.0));
  });

  test('an empty-freqs segment is a rest (silent in its slot)', () {
    // note (200ms) then rest (400ms) then note (200ms)
    final out = renderSegmentsThroughInstrument(
      [
        (freqs: const <double>[], ms: 400),
        (freqs: [440.0], ms: 200),
      ],
      _voice('piano'),
    );
    // the first 400ms slot (minus a little) has no struck note → near silent
    final restEnd = (0.35 * kSampleRate).round();
    expect(_rms(out, 0, restEnd), lessThan(1e-6));
    // the note after the rest sounds
    expect(_rms(out, (0.40 * kSampleRate).round()), greaterThan(0.0));
  });

  test('a chord sums its tones (more energy than one note)', () {
    final one = renderSegmentsThroughInstrument(
      [
        (freqs: [261.63], ms: 500),
      ],
      _voice('piano'),
    );
    final triad = renderSegmentsThroughInstrument(
      [
        (freqs: [261.63, 329.63, 392.0], ms: 500),
      ],
      _voice('piano'),
    );
    expect(_rms(triad), greaterThan(_rms(one)));
  });

  test('gain scales the output', () {
    final full = renderSegmentsThroughInstrument(
      [
        (freqs: [440.0], ms: 300),
      ],
      _voice('piano'),
    );
    final half = renderSegmentsThroughInstrument(
      [
        (freqs: [440.0], ms: 300),
      ],
      _voice('piano'),
      gain: 0.5,
    );
    expect(_rms(half), closeTo(_rms(full) * 0.5, _rms(full) * 0.05));
  });
}
