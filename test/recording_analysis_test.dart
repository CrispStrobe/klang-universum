// Analysing recorded audio FILES (not just live mic): analyzeRecording decodes
// a PCM16 WAV and runs the same pitch/chord detection over it, at the file's
// own sample rate. Verified against synth-rendered recordings.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/recording_analysis.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

// A WAV recording of [segments] at [sr] (renderWav is fixed at 44.1k, so build
// the PCM + header at the requested rate explicitly).
Uint8List _wav(List<Segment> segments, {int sr = 44100}) =>
    wavBytes(renderSegments(segments, sampleRate: sr), sampleRate: sr);

Segment _note(int midi, int ms) => (freqs: [midiToFrequency(midi)], ms: ms);

void main() {
  test('a single-note recording transcribes to that note', () {
    final r = analyzeRecording(_wav([_note(69, 800)])); // A4
    expect(r.sampleRate, 44100);
    expect(r.channels, 1);
    expect(r.durationSeconds, closeTo(0.8, 0.02));
    expect(r.voiced, isNotEmpty);
    expect(r.noteRun(), [69]);
  });

  test('a two-note recording transcribes to the run', () {
    final r = analyzeRecording(_wav([_note(57, 600), _note(69, 600)])); // A3→A4
    expect(r.noteRun(), [57, 69]);
  });

  test('analysis uses the FILE sample rate (not a hardcoded 44.1k)', () {
    final r = analyzeRecording(_wav([_note(69, 800)], sr: 22050));
    expect(r.sampleRate, 22050);
    expect(r.noteRun(), [69]); // still A4, because the detector uses 22050
  });

  test('chord detection over a recording names the chord', () {
    final cMajor = (
      freqs: [
        midiToFrequency(60),
        midiToFrequency(64),
        midiToFrequency(67),
      ],
      ms: 1000
    );
    final r = analyzeRecording(_wav([cMajor]), detectChords: true);
    expect(r.chordRun(), contains('C'));
    // Without the flag, no chord track.
    final noChords = analyzeRecording(_wav([cMajor]));
    expect(noChords.chordRun(), isEmpty);
  });

  test('a silent recording yields no notes and does not crash', () {
    final r = analyzeRecording(_wav([(freqs: const <double>[], ms: 500)]));
    expect(r.voiced, isEmpty);
    expect(r.noteRun(), isEmpty);
  });

  test('a recording shorter than one window is safe (empty frames)', () {
    final r = analyzeRecording(_wav([_note(69, 5)])); // ~5 ms
    expect(r.frames, isEmpty);
    expect(r.noteRun(), isEmpty);
  });
}
