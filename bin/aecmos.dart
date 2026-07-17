// AECMOS neural MOS scoring — headless AEC-quality evaluation on the pure-Dart
// ONNX runtime (onnx_runtime_dart). This is the neural metric docs/AEC_TIER3B.md
// once listed as "deliberately NOT used" because it "would need a native ONNX
// runtime (FFI)": onnx_runtime_dart now has the conv/pooling/GRU ops AECMOS uses,
// so it runs in pure Dart. Dev-only harness (never in the app / web build).
//
//   dart run bin/aecmos.dart <model|run-id> <lpb.raw> <mic.raw> <enh.raw> <st|nst|dt>
//
// The AECMOS model is a **Microsoft AEC-Challenge** artifact (MIT), NOT bundled:
// pass a full path, or a bare run-id (1663915512 | 1663829550 | 1668423760)
// resolved from ~/.cache/onnx_runtime_dart_models/aecmos_<run-id>.onnx. The 16 kHz
// + 48 kHz models are mirrored at https://huggingface.co/cstr/aecmos-onnx:
//   hf download cstr/aecmos-onnx aecmos_1663915512.onnx \
//     --local-dir ~/.cache/onnx_runtime_dart_models
// The .raw files are headerless PCM16 mono little-endian at the model's rate
// (16 kHz for 1663915512/1663829550, 48 kHz for 1668423760); talk type is
// st (single-talk) / nst (near-end single-talk) / dt (double-talk).
import 'dart:io';
import 'dart:typed_data';

import 'aecmos/aecmos_scorer.dart';

const _knownRunIds = ['1663915512', '1663829550', '1668423760'];

/// A bare run-id resolves to the shared model cache; anything else is a path.
/// The cache convention (and the cstr/aecmos-onnx HF mirror) names the files
/// `aecmos_<run-id>.onnx`, but a bare `<run-id>.onnx` is accepted too.
String _resolveModel(String arg) {
  if (File(arg).existsSync()) return arg;
  if (_knownRunIds.contains(arg)) {
    final home = Platform.environment['HOME'] ?? '';
    final dir = '$home/.cache/onnx_runtime_dart_models';
    for (final name in ['aecmos_$arg.onnx', '$arg.onnx']) {
      if (File('$dir/$name').existsSync()) return '$dir/$name';
    }
    return '$dir/aecmos_$arg.onnx'; // canonical name for the not-found message
  }
  return arg; // fall through: the not-found / run-id checks report clearly
}

Float32List _readPcm16(String path) {
  final bytes = File(path).readAsBytesSync();
  final samples = Int16List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 2,
  );
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = samples[i] / 32768.0;
  }
  return out;
}

void main(List<String> args) {
  if (args.length != 5) {
    stderr.writeln(
      'usage: dart run bin/aecmos.dart '
      '<model|run-id> <lpb.raw> <mic.raw> <enh.raw> <st|nst|dt>',
    );
    exitCode = 64;
    return;
  }

  final modelPath = _resolveModel(args[0]);
  if (!File(modelPath).existsSync()) {
    stderr.writeln(
      'AECMOS model not found: $modelPath\n'
      'Get one (run id ${_knownRunIds.join(" / ")}) into '
      '~/.cache/onnx_runtime_dart_models/, e.g.\n'
      '  hf download cstr/aecmos-onnx aecmos_1663915512.onnx '
      '--local-dir ~/.cache/onnx_runtime_dart_models\n'
      'or pass a full path as the first argument.',
    );
    exitCode = 66;
    return;
  }

  final scorer = AecmosScorer(modelPath);
  final lpb = _readPcm16(args[1]);
  final mic = _readPcm16(args[2]);
  final enh = _readPcm16(args[3]);
  final scores = scorer.score(args[4], lpb, mic, enh);
  stdout.writeln(
    'AECMOS — echo MOS: ${scores.echoMos.toStringAsFixed(6)}, '
    'other (degradation) MOS: ${scores.otherMos.toStringAsFixed(6)}',
  );
}
