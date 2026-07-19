// lib/core/audio/recording_analysis.dart
//
// Run the pitch/chord analysis over a RECORDED audio file, not just the live
// mic. The detection core is already stream-based ([StreamingAudioAnalyzer]);
// this decodes a PCM16 WAV, downmixes to mono, and slides the analyzer across
// the whole recording at the FILE's own sample rate. Pure + Flutter-free, so
// both the app and `bin/listen.dart` share one tested implementation, and the
// detector hardening (non-finite/degenerate frames → silence) protects it.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/chroma_analysis.dart';
import 'package:comet_beat/core/audio/pitch_analysis.dart';
import 'package:comet_beat/core/audio/streaming_analyzer.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

/// The result of analysing one recording: its format + the per-window readings.
class RecordingAnalysis {
  const RecordingAnalysis({
    required this.sampleRate,
    required this.channels,
    required this.durationSeconds,
    required this.frames,
  });

  final int sampleRate;
  final int channels;
  final double durationSeconds;

  /// One [AnalyzerFrame] per completed window (pitch, and chord when analysed
  /// with [detectChords]).
  final List<AnalyzerFrame> frames;

  /// The windows that read a confident pitch.
  Iterable<AnalyzerFrame> get voiced => frames.where((f) => f.pitch.hasPitch);

  /// A rough monophonic transcription: the sequence of detected notes (nearest
  /// MIDI), collapsing consecutive equal notes and dropping unvoiced windows.
  List<int> noteRun() {
    final out = <int>[];
    for (final f in frames) {
      if (!f.pitch.hasPitch) continue;
      final midi = f.pitch.nearestMidi;
      if (out.isEmpty || out.last != midi) out.add(midi);
    }
    return out;
  }

  /// The best chord over time (name per window), collapsing repeats. Empty
  /// unless the recording was analysed with [detectChords].
  List<String> chordRun() {
    final out = <String>[];
    for (final f in frames) {
      final name = f.chord?.best?.name;
      if (name == null) continue;
      if (out.isEmpty || out.last != name) out.add(name);
    }
    return out;
  }
}

/// Analyse a PCM16 WAV [wavBytes]: pitch (and optionally chords when
/// [detectChords]) over sliding windows, at the file's own sample rate. Any
/// channel count downmixes to mono. Throws only if [wavBytes] isn't a readable
/// PCM WAV (see [readWavPcm16]); a valid-but-odd file (silent, tiny, unusual
/// rate) yields short/empty results rather than crashing.
RecordingAnalysis analyzeRecording(
  Uint8List wavBytes, {
  double a4 = kDefaultA4,
  bool detectChords = false,
}) {
  final wav = readWavPcm16(wavBytes);
  final mono = wavToMonoFloat(wav);
  final analyzer = StreamingAudioAnalyzer(
    detector: PitchDetector(sampleRate: wav.sampleRate, a4: a4),
    chordDetector:
        detectChords ? ChordDetector(sampleRate: wav.sampleRate, a4: a4) : null,
  );
  return RecordingAnalysis(
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    durationSeconds: wav.sampleRate > 0 ? mono.length / wav.sampleRate : 0,
    frames: analyzer.addSamples(mono),
  );
}
