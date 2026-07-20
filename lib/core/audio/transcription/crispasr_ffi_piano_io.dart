// Native CrispASR ggml PIANO transcription (CrispasrSession.pianoNotes, crispasr
// 0.8.17+): resample the mono audio to the model's rate, run pianoNotes, map its
// PianoNote records onto our NoteEvent contract. dart:io only. Null when the
// ggml runtime/model isn't available here → the resolver falls back to the
// pure-Dart onnx Basic Pitch.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_session_io.dart';
import 'package:comet_beat/core/audio/transcription/route.dart'
    show NeuralTranscriber;
// For the CrispasrSession type; hide the PitchFrame that collides with ours.
import 'package:crispasr/crispasr.dart' hide PitchFrame;

// PianoNote's numeric fields cross the session seam as `num` (a cross-file
// record-inference quirk), so pin them to the NoteEvent field types here.
int _i(Object? v) => (v as num).toInt();
double _d(Object? v) => (v as num).toDouble();

/// A CrispASR-FFI piano [NeuralTranscriber], or null when the piano backend/
/// model/lib isn't available. [download] fetches the GGUF if not cached.
Future<NeuralTranscriber?> loadCrispasrPianoFfi({bool download = false}) async {
  final CrispasrSession? session =
      openCrispasrSession('piano-transcription', download: download);
  if (session == null) return null;
  final target = session.pianoSampleRate; // 16 kHz for the Kong model
  return (Float64List mono, int sampleRate) async {
    if (mono.isEmpty) return const <NoteEvent>[];
    final at =
        sampleRate == target ? mono : resampleLinear(mono, sampleRate / target);
    final pcm = Float32List(at.length);
    for (var i = 0; i < at.length; i++) {
      pcm[i] = at[i].toDouble();
    }
    try {
      // PianoNote {midi, onMs, offMs, velocity} → our NoteEvent.
      final events = <NoteEvent>[];
      for (final n in session.pianoNotes(pcm)) {
        // velocity is a loudness estimate, not a confidence — use it as a 0–1
        // strength proxy (documented; better than a flat constant).
        final NoteEvent e = (
          midi: _i(n.midi),
          onMs: _d(n.onMs),
          offMs: _d(n.offMs),
          confidence: (_d(n.velocity) / 127).clamp(0.0, 1.0).toDouble(),
        );
        events.add(e);
      }
      return events;
    } catch (_) {
      return const <NoteEvent>[];
    }
  };
}
