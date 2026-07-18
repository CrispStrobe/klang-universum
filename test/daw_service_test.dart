// The shared DAW arrangement service: modules add clips, the arranger bakes.
// Pure, headless.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/daw_timeline.dart';
import 'package:comet_beat/core/services/daw_service.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSource _tone(double level, int samples) =>
    SampleSource(Float64List(samples)..fillRange(0, samples, level));

bool _silent(Iterable<double> pcm) => pcm.every((s) => s == 0);

void main() {
  test('starts with two empty tracks', () {
    final s = DawService();
    expect(s.timeline.tracks.length, 2);
    expect(s.clipCount, 0);
    expect(s.bake(), isEmpty);
  });

  test('addClip appends to the target track and lays clips out in time', () {
    final s = DawService()
      ..addClip(_tone(0.3, 100))
      ..addClip(_tone(0.3, 100), track: 1);
    expect(s.clipCount, 2);
    // Successive sends step 2 s apart, so the bake runs well past the first clip.
    expect(s.bake().length, greaterThan(100));
    // A track index beyond the existing lanes auto-creates tracks.
    s.addClip(_tone(0.3, 10), track: 4);
    expect(s.timeline.tracks.length, 5);
    expect(s.clipCount, 3);
  });

  test('muting a track removes it from the bake', () {
    final s = DawService()..addClip(_tone(0.5, 100)); // track 0 only
    expect(_silent(s.bake()), isFalse);
    s.toggleTrackMute(0);
    expect(s.bake(), isEmpty); // the only sounding track is muted
  });

  test('clear empties every track and the cache', () {
    final s = DawService()
      ..addClip(_tone(0.5, 100))
      ..addClip(_tone(0.5, 100), track: 1);
    expect(s.clipCount, 2);
    s.clear();
    expect(s.clipCount, 0);
    expect(s.bake(), isEmpty);
  });
}
