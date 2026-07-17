// bin/aec.dart
//
// Command-line harness for acoustic echo cancellation — runs the SAME pure-Dart
// linear canceller the app's Tier-3b jam AEC is a cleanroom port of, headlessly,
// over files or live pipes. The point: test AEC on real or synthetic audio
// without a device or the native plugin. Three ways in:
//
//   Self-test (synthesize a band + an instrument + the room echo, no audio):
//     dart run bin/aec.dart --selftest --detect
//
//   Files (a captured mic recording + the reference that was played):
//     dart run bin/aec.dart --mic captured.wav --ref played.wav --out clean.wav
//     dart run bin/aec.dart --mic captured.wav --ref played.wav --detect
//
//   Live pipe — interleaved STEREO PCM16 in (ch0 = mic, ch1 = reference),
//   cleaned MONO PCM16 out:
//     # build the stereo stream with sox (mic = default device, ref = a WAV):
//     sox -M -t coreaudio default -c 1 groove.wav -c 1 -t raw -b 16 -e signed -r 44100 - \
//       | dart run bin/aec.dart --stdin > cleaned.raw
//     # or chain straight into the pitch detector to see what survived:
//     ... | dart run bin/aec.dart --stdin | dart run bin/listen.dart --stdin
//     # or let this tool detect it:
//     ... | dart run bin/aec.dart --stdin --detect
//
// The BlackHole loopback rig (see docs/AEC_TIER3B.md) is the self-driven
// acoustic version: play the reference out, capture (mic|ref) as a stereo
// stream, pipe it here, confirm the near-end survives and the echo is gone.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:klang_universum/core/audio/aec_offline.dart';
import 'package:klang_universum/core/audio/pitch_analysis.dart';
import 'package:klang_universum/core/audio/streaming_analyzer.dart';
import 'package:klang_universum/core/audio/synth.dart';
import 'package:klang_universum/core/audio/wav_io.dart';

const _usage = '''
AEC (acoustic echo cancellation) CLI — cancel the played reference out of a mic.

Usage:
  dart run bin/aec.dart --selftest [--detect]
  dart run bin/aec.dart --mic <captured.wav> --ref <played.wav> [--out <clean.wav>] [--delay N] [--detect]
  dart run bin/aec.dart --stdin [--delay N] [--rate hz] [--detect]   # interleaved stereo PCM16 in

Options:
  --selftest      Synthesize a band + instrument + room echo, cancel, report.
  --mic <file>    Captured near-end+echo WAV (file mode).
  --ref <file>    Reference (what was played) WAV (file mode).
  --out <file>    Write the cleaned near-end as a WAV (file mode).
  --stdin         Read interleaved stereo PCM16 (ch0=mic, ch1=ref) from stdin;
                  write cleaned mono PCM16 to stdout (or notes with --detect).
  --delay <n>     Fixed reference->mic delay in samples (streaming/file; file
                  mode estimates it by cross-correlation when omitted).
  --rate <hz>     Sample rate for --stdin / --detect (default 44100).
  --detect        Run the pitch detector on the cleaned output and print notes
                  (proves which pitch survives the cancellation).
  -h, --help      Show this help.
''';

Future<void> main(List<String> argv) async {
  final args = _Args(argv);
  if (args.flag('help') || args.flag('h') || argv.isEmpty) {
    stdout.writeln(_usage);
    return;
  }
  final rate = int.tryParse(args.value('rate') ?? '') ?? kSampleRate;
  final detect = args.flag('detect');
  final delay = int.tryParse(args.value('delay') ?? '');

  if (args.flag('selftest')) {
    _selftest(rate: rate, detect: detect);
    return;
  }
  if (args.flag('stdin')) {
    await _stream(rate: rate, refDelay: delay ?? 0, detect: detect);
    return;
  }
  if (args.value('mic') != null && args.value('ref') != null) {
    _files(
      micPath: args.value('mic')!,
      refPath: args.value('ref')!,
      outPath: args.value('out'),
      delay: delay,
      detect: detect,
    );
    return;
  }
  stderr.writeln('Nothing to do. Try --selftest, --stdin, or --mic/--ref.\n');
  stdout.writeln(_usage);
  exitCode = 2;
}

/// A steady tone (mono float) at [midi].
Float64List _tone(int midi, int n, int rate, {double amp = 0.4}) {
  final f = midiToFrequency(midi);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * sin(2 * pi * f * i / rate);
  }
  return out;
}

/// A short room impulse response applied to [ref], delayed by [delay] samples.
Float64List _roomEcho(Float64List ref, {int delay = 200}) {
  const h = [0.7, -0.3, 0.18, -0.08];
  final out = Float64List(ref.length);
  for (var t = 0; t < ref.length; t++) {
    var acc = 0.0;
    for (var j = 0; j < h.length; j++) {
      final s = t - delay - j;
      if (s >= 0) acc += h[j] * ref[s];
    }
    out[t] = acc;
  }
  return out;
}

/// Synthetic end-to-end check, two properties:
///  1. Echo-only: cancelling the reference out of its pure room echo gives a
///     high ERLE (the cancellation is strong).
///  2. Double-talk: with an "instrument" note also present, the cleaned signal
///     reads the instrument, not the "band" — the speaker is gone, the player
///     survives. (ERLE is deliberately NOT the metric here: preserving the
///     near-end keeps residual energy up, so ERLE stays low by design.)
void _selftest({required int rate, required bool detect}) {
  const bandMidi = 48; // C3 "band" (the speaker/reference)
  const instrumentMidi = 69; // A4 "instrument" (must survive)
  final n = rate * 2; // 2 seconds
  final ref = _tone(bandMidi, n, rate, amp: 0.5);

  // 1. Echo-only cancellation strength.
  final echoOnly = _roomEcho(ref);
  final r1 = cancelEcho(echoOnly, ref);
  final tail = r1.cleaned.length ~/ 2;
  final erle = erleDb(
    Float64List.sublistView(echoOnly, tail, r1.cleaned.length),
    Float64List.sublistView(r1.cleaned, tail),
  );
  stderr.writeln('estimated delay: ${r1.delay} samples');
  stderr.writeln('echo-only ERLE: converged tail ${erle.toStringAsFixed(1)} dB '
      '(whole ${r1.erleDb.toStringAsFixed(1)} dB)');

  // 2. Double-talk: instrument + the band's echo → cancel → what survives?
  final near = _tone(instrumentMidi, n, rate, amp: 0.35);
  final mic = Float64List(n);
  for (var i = 0; i < n; i++) {
    mic[i] = echoOnly[i] + near[i];
  }
  final r2 = cancelEcho(mic, ref);
  final heard = _detectDominant(r2.cleaned, rate);
  final rawHeard = _detectDominant(mic, rate);
  stderr.writeln('double-talk: raw mic reads '
      '${rawHeard == null ? "—" : _noteName(rawHeard)}, '
      'cleaned reads ${heard == null ? "—" : _noteName(heard)}  '
      '(instrument ${_noteName(instrumentMidi)}, band ${_noteName(bandMidi)})');

  final erleOk = erle > 15;
  final surviveOk = heard == instrumentMidi;
  final ok = erleOk && surviveOk;
  if (detect && heard != null) _printFrameNote(r2.cleaned, rate);
  stdout.writeln(
    ok
        ? 'PASS'
        : 'FAIL${erleOk ? "" : " (weak ERLE)"}'
            '${surviveOk ? "" : " (instrument not recovered)"}',
  );
  if (!ok) exitCode = 1;
}

/// Print the detected note of [signal]'s steady middle (verbose --detect).
void _printFrameNote(Float64List signal, int rate) {
  final detector = PitchDetector(sampleRate: rate);
  final w = detector.windowSize;
  if (signal.length < w) return;
  final start = (signal.length - w) ~/ 2;
  final r = detector.analyze(Float64List.sublistView(signal, start, start + w));
  if (r.hasPitch) _printFrame(r);
}

/// File mode: cancel [refPath] out of [micPath], report, optionally write/detect.
void _files({
  required String micPath,
  required String refPath,
  String? outPath,
  int? delay,
  required bool detect,
}) {
  final micWav = readWavPcm16(File(micPath).readAsBytesSync());
  final refWav = readWavPcm16(File(refPath).readAsBytesSync());
  if (micWav.sampleRate != refWav.sampleRate) {
    stderr.writeln('mic and ref sample rates differ '
        '(${micWav.sampleRate} vs ${refWav.sampleRate})');
    exitCode = 2;
    return;
  }
  final sr = micWav.sampleRate;
  final result = cancelEcho(
    wavToMonoFloat(micWav),
    wavToMonoFloat(refWav),
    delay: delay,
  );
  stderr.writeln('delay ${result.delay} samples '
      '(${(result.delay * 1000 / sr).toStringAsFixed(1)} ms), '
      'ERLE ${result.erleDb.toStringAsFixed(1)} dB');

  if (outPath != null) {
    final pcm = Int16List(result.cleaned.length);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = (result.cleaned[i].clamp(-1.0, 1.0) * 32767).round();
    }
    File(outPath).writeAsBytesSync(wavBytes(pcm, sampleRate: sr));
    stderr.writeln('wrote cleaned WAV: $outPath');
  }
  if (detect) {
    final heard = _detectDominant(result.cleaned, sr);
    stdout.writeln('cleaned reads: ${heard == null ? "—" : _noteName(heard)}');
  }
}

/// Streaming mode: interleaved stereo PCM16 on stdin → cleaned mono PCM16 on
/// stdout (or detected notes with --detect).
Future<void> _stream({
  required int rate,
  required int refDelay,
  required bool detect,
}) async {
  final aec = StreamingEchoCanceller(refDelay: refDelay);
  final analyzer = detect
      ? StreamingAudioAnalyzer(detector: PitchDetector(sampleRate: rate))
      : null;
  if (detect) {
    stderr.writeln('AEC + detect on stdin: stereo PCM16 @ $rate Hz. '
        'Ctrl-C to stop.');
  }

  Future<void> handle(Uint8List cleaned) async {
    if (cleaned.isEmpty) return;
    if (analyzer != null) {
      for (final frame in analyzer.addPcm16(cleaned)) {
        if (frame.pitch.hasPitch) _printFrame(frame.pitch);
      }
    } else {
      stdout.add(cleaned);
    }
  }

  await for (final chunk in stdin) {
    await handle(aec.addInterleavedPcm16(_asUint8(chunk)));
  }
  await handle(aec.flush());
  stderr.writeln('ERLE ${aec.erleDb.toStringAsFixed(1)} dB');
}

Uint8List _asUint8(List<int> data) =>
    data is Uint8List ? data : Uint8List.fromList(data);

/// The dominant note in [signal], via the pitch detector over a centred window,
/// or null if none — used by the self-test / --detect one-shot report.
int? _detectDominant(Float64List signal, int rate) {
  final detector = PitchDetector(sampleRate: rate);
  final w = detector.windowSize;
  if (signal.length < w) return null;
  final start = (signal.length - w) ~/ 2; // skip warmup, read the steady middle
  final window = Float64List.sublistView(signal, start, start + w);
  final r = detector.analyze(window);
  return r.hasPitch ? r.nearestMidi : null;
}

void _printFrame(PitchReading p) {
  stdout.writeln('${p.noteName.padRight(3)}  '
      '${p.cents >= 0 ? '+' : ''}${p.cents.toStringAsFixed(0).padLeft(3)}c  '
      '${p.frequency.toStringAsFixed(1).padLeft(7)}Hz  '
      'clarity ${p.clarity.toStringAsFixed(2)}');
}

const _names = [
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
String _noteName(int midi) => '${_names[midi % 12]}${(midi ~/ 12) - 1}';

/// Tiny flag/value parser: `--flag`, `--key value`, `--key=value`.
class _Args {
  _Args(List<String> argv) {
    for (var i = 0; i < argv.length; i++) {
      var a = argv[i];
      if (!a.startsWith('--') && !a.startsWith('-')) continue;
      a = a.replaceFirst(RegExp('^--?'), '');
      if (a.contains('=')) {
        final eq = a.indexOf('=');
        _values[a.substring(0, eq)] = a.substring(eq + 1);
      } else if (i + 1 < argv.length && !argv[i + 1].startsWith('-')) {
        _values[a] = argv[++i];
      } else {
        _flags.add(a);
      }
    }
  }

  final _flags = <String>{};
  final _values = <String, String>{};

  bool flag(String name) => _flags.contains(name) || _values.containsKey(name);
  String? value(String name) => _values[name];
}
