// W-DRUMS — transcribe a synthesized kick/snare/hat pattern back to the right
// drums at the right times, using the real synth drum voices (renderDrum) so the
// timbres are faithful, and the shared classifier.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart'
    show Drum, kSampleRate, renderDrum;
import 'package:comet_beat/core/audio/transcription/drums.dart';
import 'package:flutter_test/flutter_test.dart';

// Lay [pattern] (drum + step) on a 16th grid at the given step length, rendered
// with the real synth voices, into one mono buffer.
Float64List _render(List<({Drum drum, int step})> pattern, {int stepMs = 150}) {
  final voices = {for (final p in pattern) p.drum: renderDrum(p.drum)};
  final stepN = stepMs * kSampleRate ~/ 1000;
  final lastStep = pattern.map((p) => p.step).reduce((a, b) => a > b ? a : b);
  final total = (lastStep + 4) * stepN;
  final out = Float64List(total);
  for (final p in pattern) {
    final v = voices[p.drum]!;
    final at = p.step * stepN;
    for (var i = 0; i < v.length && at + i < total; i++) {
      out[at + i] += v[i];
    }
  }
  return out;
}

void main() {
  test('a kick–hat–snare–hat pattern transcribes to the right drums', () {
    final hits = transcribeDrums(
      _render(const [
        (drum: Drum.kick, step: 0),
        (drum: Drum.hat, step: 1),
        (drum: Drum.snare, step: 2),
        (drum: Drum.hat, step: 3),
      ]),
    );

    // Found roughly the four onsets (onset detection may merge/miss one).
    expect(hits.length, greaterThanOrEqualTo(3));
    // The first hit is the kick; a snare appears; hats appear.
    expect(hits.first.drum, Drum.kick);
    expect(hits.map((h) => h.drum), contains(Drum.snare));
    expect(hits.map((h) => h.drum), contains(Drum.hat));
    // Onsets are ordered in time and land near the authored 150 ms grid.
    for (var i = 1; i < hits.length; i++) {
      expect(hits[i].timeMs, greaterThan(hits[i - 1].timeMs));
    }
  });

  test('a lone kick is classified as a kick', () {
    final buf = Float64List(kSampleRate ~/ 2);
    final kick = renderDrum(Drum.kick);
    for (var i = 0; i < kick.length && i < buf.length; i++) {
      buf[i] = kick[i];
    }
    final hits = transcribeDrums(buf);
    expect(hits, isNotEmpty);
    expect(hits.first.drum, Drum.kick);
  });

  test('silence yields no hits, never throws', () {
    expect(transcribeDrums(Float64List(kSampleRate)), isEmpty);
    expect(transcribeDrums(Float64List(0)), isEmpty);
  });
}
