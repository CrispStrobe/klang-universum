// bin/transcribe.dart
//
// The UNIFIED headless transcription CLI: one entry point over every backend +
// model the decision framework can run from `dart run` (i.e. all but onnxFfi —
// the native-ORT plugin transitively needs the Flutter engine, so it's GUI-only
// and deliberately absent here). A WAV goes in; notes (mono F0 → note chain),
// polyphonic notes, or chords come out.
//
//   dart run bin/transcribe.dart audio.wav [options]
//
//   --task notes|poly|chords   what to produce (default notes)
//   --backend auto|dart|onnx|crispasr
//                              which runtime (default auto: crispasr → onnx →
//                              pure-Dart for F0). poly/chords are onnx-only.
//   --f0 pyin|crepe|rmvpe      the F0 model for `notes` (default: per backend —
//                              dart→pyin, onnx→crepe, crispasr→crepe)
//   --a4 440                   reference pitch
//   --f0-dump                  print the raw pitch track instead of notes
//   --json                     machine-readable output
//
// Each neural model auto-downloads on first use through its own *_model_store
// (MIT weights on the onnx_runtime_dart models-v1 release; crepe GGUF via
// CrispASR's registry). Convert to mono WAV first, e.g.
//   ffmpeg -i in.ogg -ac 1 -ar 44100 -c:a pcm_s16le out.wav
//
// Per-model CLIs still exist (transcribe_crepe/_basicpitch/_chords/_crispasr);
// this one is the single dispatcher over all of them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:comet_beat/core/audio/transcription/basic_pitch.dart';
import 'package:comet_beat/core/audio/transcription/basic_pitch_model_store.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_pitch.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_pitch.dart';
import 'package:comet_beat/core/audio/transcription/harmony.dart';
import 'package:comet_beat/core/audio/transcription/harmony_model_store.dart';
import 'package:comet_beat/core/audio/transcription/pyin.dart' show pyinF0;
import 'package:comet_beat/core/audio/transcription/rmvpe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/wav_io.dart';

const _names = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
];
String _noteName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';

double _optD(List<String> a, String f, double d) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? double.parse(a[i + 1]) : d;
}

String _optS(List<String> a, String f, String d) {
  final i = a.indexOf(f);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run bin/transcribe.dart audio.wav '
      '[--task notes|poly|chords] [--backend auto|dart|onnx|crispasr] '
      '[--f0 pyin|crepe|rmvpe] [--a4 440] [--f0-dump] [--json]',
    );
    exit(64);
  }
  final path = positional.first;
  if (!File(path).existsSync()) {
    stderr.writeln('no such file: $path');
    exit(66);
  }
  final task = _optS(args, '--task', 'notes');
  final backend = _optS(args, '--backend', 'auto');
  final json = args.contains('--json');
  final a4 = _optD(args, '--a4', 440);

  final wav = readWavPcm16(File(path).readAsBytesSync());
  final mono = wavToMonoFloat(wav);
  stderr.writeln(
    'loaded $path — ${wav.sampleRate} Hz, ${wav.channels}ch, '
    '${(mono.length / wav.sampleRate).toStringAsFixed(2)} s',
  );
  final sw = Stopwatch()..start();

  switch (task) {
    case 'poly':
      final model = await BasicPitchModelStore().load();
      final notes =
          basicPitchTranscribe(model: model, mono, sampleRate: wav.sampleRate);
      sw.stop();
      _printNotes(notes, sw, json);
    case 'chords':
      final bundle = await HarmonyModelStore().load();
      final chords = estimateChords(
        mono,
        model: bundle.model,
        cqt: bundle.cqt,
        sampleRate: wav.sampleRate,
      );
      sw.stop();
      _printChords(chords, sw, json);
    case 'notes':
      final f0 = await _resolveF0(backend, _optS(args, '--f0', ''));
      if (args.contains('--f0-dump')) {
        final track = f0 == null
            ? pyinF0(mono, sampleRate: wav.sampleRate)
            : await f0(mono, wav.sampleRate);
        sw.stop();
        _printTrack(track, sw, json);
        return;
      }
      final notes = await transcribeMonophonic(
        mono,
        sampleRate: wav.sampleRate,
        a4: a4,
        f0: f0,
      );
      sw.stop();
      _printNotes(notes, sw, json);
    default:
      stderr.writeln('unknown --task "$task" (notes|poly|chords)');
      exit(64);
  }
}

/// Resolve the F0 estimator for the `notes` task from the backend + model
/// choice. Null ⇒ the pure-Dart pYIN default (web-safe, no model).
Future<F0Estimator?> _resolveF0(String backend, String model) async {
  Future<F0Estimator?> onnx() async {
    final m = model.isEmpty ? 'crepe' : model;
    if (m == 'rmvpe') return RmvpeModelStore().estimator();
    if (m == 'crepe') return crepeF0Estimator();
    return null; // pyin
  }

  Future<F0Estimator?> crispasr() async =>
      await crispasrFfiCrepeF0(download: true) ?? crispasrCliCrepeF0();

  switch (backend) {
    case 'dart':
      return null; // pyin
    case 'onnx':
      return onnx();
    case 'crispasr':
      final f0 = await crispasr();
      if (f0 == null) {
        stderr.writeln('crispasr backend unavailable — falling back to pyin');
      }
      return f0;
    case 'auto':
    default:
      // Fastest-first: crispasr ggml → onnx (crepe/rmvpe) → pyin.
      final ggml = await crispasr();
      if (ggml != null) {
        stderr.writeln('backend: crispasr (ggml CREPE)');
        return ggml;
      }
      final o = await onnx();
      if (o != null) {
        stderr.writeln('backend: onnx (${model.isEmpty ? 'crepe' : model})');
        return o;
      }
      stderr.writeln('backend: pure-Dart (pYIN)');
      return null;
  }
}

void _printNotes(List<NoteEvent> events, Stopwatch sw, bool json) {
  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final n in events)
          {
            'midi': n.midi,
            'name': _noteName(n.midi),
            'onMs': n.onMs,
            'offMs': n.offMs,
            'confidence': n.confidence,
          },
      ]),
    );
    return;
  }
  stdout.writeln('${events.length} notes  (${sw.elapsedMilliseconds} ms):');
  stdout.writeln('  #   note   start      end     conf');
  for (var i = 0; i < events.length; i++) {
    final n = events[i];
    stdout.writeln(
      '${(i + 1).toString().padLeft(3)}  '
      '${_noteName(n.midi).padRight(5)} '
      '${(n.onMs / 1000).toStringAsFixed(3).padLeft(7)}s '
      '${(n.offMs / 1000).toStringAsFixed(3).padLeft(7)}s '
      '${n.confidence.toStringAsFixed(2).padLeft(6)}',
    );
  }
}

void _printChords(List<ChordEvent> chords, Stopwatch sw, bool json) {
  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final c in chords)
          {
            'label': c.label,
            'rootPc': c.rootPc,
            'quality': c.quality,
            'onMs': c.onMs,
            'offMs': c.offMs,
          },
      ]),
    );
    return;
  }
  stdout.writeln('${chords.length} chords  (${sw.elapsedMilliseconds} ms):');
  stdout.writeln('  #   chord    start      end');
  for (var i = 0; i < chords.length; i++) {
    final c = chords[i];
    stdout.writeln(
      '${(i + 1).toString().padLeft(3)}  '
      '${c.label.padRight(7)} '
      '${(c.onMs / 1000).toStringAsFixed(3).padLeft(7)}s '
      '${(c.offMs / 1000).toStringAsFixed(3).padLeft(7)}s',
    );
  }
}

void _printTrack(PitchTrack track, Stopwatch sw, bool json) {
  if (json) {
    stdout.writeln(
      jsonEncode([
        for (final f in track)
          {'timeMs': f.timeMs, 'f0Hz': f.f0Hz, 'voicedProb': f.voicedProb},
      ]),
    );
    return;
  }
  stderr.writeln('${track.length} frames (${sw.elapsedMilliseconds} ms):');
  stdout.writeln('   time(s)     f0(Hz)   voiced');
  for (final f in track) {
    stdout.writeln(
      '${(f.timeMs / 1000).toStringAsFixed(3).padLeft(9)}  '
      '${f.f0Hz.toStringAsFixed(2).padLeft(9)}  '
      '${f.voicedProb.toStringAsFixed(3).padLeft(7)}',
    );
  }
}
