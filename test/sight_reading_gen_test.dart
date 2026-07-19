import 'package:comet_beat/features/games/sight_reading/sight_reading_gen.dart';
import 'package:flutter_test/flutter_test.dart';

// The C-major range the generator draws from (C4..C5).
const _scale = {60, 62, 64, 65, 67, 69, 71, 72};

void main() {
  test('is deterministic for a given seed', () {
    final a = sightReadingChart(42);
    final b = sightReadingChart(42);
    expect(
      a.notes.map((n) => (n.midi, n.startBeat, n.beats)),
      b.notes.map((n) => (n.midi, n.startBeat, n.beats)),
    );
  });

  test('different seeds give different tunes (non-repeating)', () {
    final pitches = {
      for (final seed in [1, 2, 3, 4, 5])
        sightReadingChart(seed).notes.map((n) => n.midi).join(','),
    };
    // Five seeds should yield at least a few distinct melodies.
    expect(pitches.length, greaterThan(3));
  });

  test('every note is in key and inside the singable range', () {
    for (final seed in List.generate(30, (i) => i)) {
      for (final n in sightReadingChart(seed).notes) {
        expect(_scale.contains(n.midi), isTrue, reason: 'midi ${n.midi}');
      }
    }
  });

  test('fills exactly the bars it promises and resolves to the tonic', () {
    final chart = sightReadingChart(7); // default 4 bars
    final total = chart.notes.fold<double>(0, (s, n) => s + n.beats);
    expect(total, closeTo(16, 1e-9)); // 4 bars × 4 beats
    expect(chart.notes.first.startBeat, 0);
    expect(chart.notes.last.midi % 12, 0); // ends on C (tonic)
    expect(chart.notes.last.startBeat, 15); // the final beat
  });

  test('carries a tempo and sings octave-agnostically', () {
    final chart = sightReadingChart(1, bpm: 100);
    expect(chart.bpm, 100);
    expect(chart.octaveAgnostic, isTrue);
    expect(chart.notes, isNotEmpty);
  });

  test('a longer exercise scales with bars', () {
    final total = sightReadingChart(3, bars: 8)
        .notes
        .fold<double>(0, (s, n) => s + n.beats);
    expect(total, closeTo(32, 1e-9));
  });
}
