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

  test('the starter tier (0★) is gentle: 5-note range, quarters only', () {
    // Across many seeds, level 0 never leaves C4..G4 and never uses eighths.
    const starter = {60, 62, 64, 65, 67}; // C D E F G
    for (final seed in List.generate(40, (i) => i)) {
      final chart = sightReadingChart(seed, stars: 0);
      for (final n in chart.notes) {
        expect(starter.contains(n.midi), isTrue, reason: 'midi ${n.midi}');
        expect(n.beats, 1.0, reason: 'no eighths at 0★');
      }
      expect(chart.bpm, 80); // gentler default tempo
    }
  });

  test('higher tiers open up range, eighths and tempo', () {
    // Eighths (beats 0.5) appear at 2★+ but never at 0★.
    bool hasEighths(int stars) => List.generate(20, (i) => i)
        .expand((s) => sightReadingChart(s, stars: stars).notes)
        .any((n) => n.beats == 0.5);
    expect(hasEighths(0), isFalse);
    expect(hasEighths(2), isTrue);

    // The top tier uses the full octave and a brisker tempo.
    final top = sightReadingChart(1, stars: 3);
    expect(top.bpm, 104);

    // Every tier still stays in C major and resolves to the tonic.
    for (final stars in [0, 1, 2, 3]) {
      final chart = sightReadingChart(9, stars: stars);
      for (final n in chart.notes) {
        expect(_scale.contains(n.midi), isTrue);
      }
      expect(chart.notes.last.midi % 12, 0);
    }
  });

  test('still deterministic per (seed, tier)', () {
    final a = sightReadingChart(5, stars: 3);
    final b = sightReadingChart(5, stars: 3);
    expect(
      a.notes.map((n) => (n.midi, n.startBeat, n.beats)),
      b.notes.map((n) => (n.midi, n.startBeat, n.beats)),
    );
  });

  test('opens on a stable degree that varies with the seed', () {
    expect(sightReadingChart(0).notes.first.midi, 60); // tonic C
    expect(sightReadingChart(1).notes.first.midi, 67); // dominant G
    expect(sightReadingChart(2).notes.first.midi, 64); // mediant E
  });

  test('closes with a stepwise cadence (2̂ → 1̂, D → C)', () {
    for (final seed in [1, 7, 13, 20, 33]) {
      final notes = sightReadingChart(seed).notes;
      expect(notes[notes.length - 2].midi, 62, reason: 'penultimate D');
      expect(notes.last.midi, 60, reason: 'final C');
    }
  });

  group('minor mode (A natural minor)', () {
    // A B C D E F G A — the relative minor, still accidental-free.
    const aMinor = {57, 59, 60, 62, 64, 65, 67, 69};

    test('draws only from A minor and resolves to A', () {
      for (final seed in List.generate(30, (i) => i)) {
        final chart = sightReadingChart(seed, minor: true, stars: 2);
        expect(chart.name, contains('minor'));
        for (final n in chart.notes) {
          expect(aMinor.contains(n.midi), isTrue, reason: 'midi ${n.midi}');
        }
        expect(chart.notes.last.midi, 57); // tonic A
        expect(chart.notes[chart.notes.length - 2].midi, 59); // 2̂ = B
      }
    });

    test('opens on A / E / C by seed and is deterministic', () {
      int firstOf(int seed) =>
          sightReadingChart(seed, minor: true).notes.first.midi;
      expect(firstOf(0), 57); // A tonic
      expect(firstOf(1), 64); // E dominant
      expect(firstOf(2), 60); // C mediant
      final a = sightReadingChart(5, minor: true, stars: 3);
      final b = sightReadingChart(5, minor: true, stars: 3);
      expect(
        a.notes.map((n) => (n.midi, n.startBeat, n.beats)),
        b.notes.map((n) => (n.midi, n.startBeat, n.beats)),
      );
    });

    test('the 0★ minor tier stays in the low five notes, quarters only', () {
      const starter = {57, 59, 60, 62, 64}; // A B C D E
      for (final seed in List.generate(20, (i) => i)) {
        for (final n in sightReadingChart(seed, minor: true, stars: 0).notes) {
          expect(starter.contains(n.midi), isTrue, reason: 'midi ${n.midi}');
          expect(n.beats, 1.0);
        }
      }
    });
  });
}
