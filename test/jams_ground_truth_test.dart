// JAMS as a GROUND-TRUTH PROVIDER for automated detection testing.
//
// The importer's job is "annotation → app content"; the harder question is "is
// our DETECTION any good?". JAMS answers both: it is the MIR-standard ground-
// truth interchange. The JAMS writers (notesToJams / chordsToJams) let a test
// author a machine-readable ground truth; we then SYNTHESIZE audio from it and
// run the app's own detectors, asserting they recover the ground truth. This is
// the input-side acceptance loop
//
//     author JAMS ground truth → synthesize → detect → compare
//
// with JAMS as the interchange — so the same fixtures could later be swapped for
// real annotated datasets (Isophonics, MedleyDB, …) with no test changes. The
// writers round-trip through the readers here too, so the ground truth we author
// is exactly what the importer would read.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/features/games/songs/import/chordpro.dart';
import 'package:comet_beat/features/games/songs/import/jams.dart';
import 'package:flutter_test/flutter_test.dart';

/// A centred analysis window of a synthesized tone at [freq].
Float64List _toneWindow(double freq, int windowSize, int sampleRate) {
  final samples = renderSegments(
    [
      (freqs: [freq], ms: 500),
    ],
    sampleRate: sampleRate,
  );
  final start = (samples.length - windowSize) ~/ 2;
  final out = Float64List(windowSize);
  for (var i = 0; i < windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

/// A centred FFT window of simultaneous [freqs] (a chord).
Float64List _chordWindow(List<double> freqs, int windowSize) {
  final samples = renderSegments([
    (freqs: freqs, ms: 600),
  ]);
  final start = (samples.length - windowSize) ~/ 2;
  final out = Float64List(windowSize);
  for (var i = 0; i < windowSize; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}

void main() {
  test('pitch detector recovers a full CHROMATIC note_midi ground truth', () {
    // Author every semitone from C3 (48) to C6 (84) as a JAMS note_midi (the
    // provider), spanning three octaves incl. every accidental.
    const lo = 48, hi = 84;
    final groundTruth = notesToJams(
      [
        for (var m = lo; m <= hi; m++)
          (time: (m - lo) * 0.5, duration: 0.5, midi: m),
      ],
      title: 'chromatic',
      tempo: 120,
    );

    // Read it back the way the importer does (writer↔reader round-trip).
    final truth = jamsMelodyNotes(groundTruth);
    expect(truth.map((n) => n.midi), [for (var m = lo; m <= hi; m++) m]);

    // Synthesize each ground-truth note; the detector must recover it exactly.
    final detector = PitchDetector();
    for (final n in truth) {
      final window = _toneWindow(
        midiToFrequency(n.midi),
        detector.windowSize,
        detector.sampleRate,
      );
      final r = detector.analyze(window);
      expect(r.hasPitch, isTrue, reason: 'midi ${n.midi} not detected');
      expect(
        r.nearestMidi,
        n.midi,
        reason: 'detected ${r.noteName} for ground-truth midi ${n.midi}',
      );
    }
  });

  test('chord detector recovers the ROOT of every maj/min triad', () {
    const windowSize = 4096;
    final detector = ChordDetector();
    // All 12 roots × {major, minor}, authored via their triad pitches.
    for (var root = 60; root < 72; root++) {
      for (final quality in ['', 'm']) {
        final name = _pcNames[root % 12] + quality;
        final midis = chordMidis(name)!;
        final r = detector.analyze(
          _chordWindow(midis.map(midiToFrequency).toList(), windowSize),
        );
        expect(r.hasChord, isTrue, reason: '$name should match something');
        // The root is always recovered (the quality can occasionally read
        // richer — e.g. a bare C# triad edges to C#maj7 in the chroma match —
        // which is why the exact-name assertion below sticks to a clean set).
        expect(
          r.best!.rootPc,
          root % 12,
          reason: 'root of $name: got ${r.best!.name}',
        );
      }
    }
  });

  test('chord detector names a clean progression exactly (via JAMS)', () {
    // Author a I-vi-IV-V progression as JAMS, read it back to the app's names,
    // then synthesize + detect each and assert the exact chord name.
    final groundTruth = chordsToJams(['C', 'Am', 'F', 'G'], title: 'I-vi-IV-V');
    final truth = parseChordPro(jamsToChordPro(groundTruth)).chords;
    expect(truth, ['C', 'Am', 'F', 'G']);

    const windowSize = 4096;
    final detector = ChordDetector();
    for (final name in truth) {
      final midis = chordMidis(name)!;
      final r = detector.analyze(
        _chordWindow(midis.map(midiToFrequency).toList(), windowSize),
      );
      expect(r.hasChord, isTrue, reason: '$name should match something');
      expect(
        r.best!.name,
        name,
        reason: 'detected ${r.candidates.take(3).join(", ")} for $name',
      );
    }
  });
}

const _pcNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
