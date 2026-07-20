// resolveSeparator maps the config's `separation` choice + which separators are
// actually available to a concrete Separator: crispasr (--separate CLI) or onnx
// (Open-Unmix), auto-preferring crispasr; null when none is present or the user
// forces a backend that has no separator (there is no pure-Dart separator).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart'
    show Separator, Stems;
import 'package:comet_beat/features/games/transcribe/transcribe_engines.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Stems> _fakeSep(Float64List mono, int sr) async =>
    (vocals: mono, bass: null, drums: null, other: null);

void main() {
  const cfg = TranscriptionEngineConfig();

  test('auto, both present → crispasr wins', () async {
    final s = await resolveSeparator(
      cfg,
      isWeb: false,
      loadCrispasr: ({bool download = false}) async => _fakeSep,
      loadOnnx: ({bool download = false}) async => _fakeSep,
    );
    expect(s, isNotNull);
  });

  test('auto, only onnx present → onnx (UMX)', () async {
    var used = false;
    Future<Stems> onnx(Float64List m, int sr) async {
      used = true;
      return (vocals: m, bass: null, drums: null, other: null);
    }

    final s = await resolveSeparator(
      cfg,
      isWeb: false,
      loadCrispasr: ({bool download = false}) async => null,
      loadOnnx: ({bool download = false}) async => onnx,
    );
    expect(s, isNotNull);
    await s!(Float64List(0), 44100);
    expect(used, isTrue);
  });

  test('nothing available → null (single-part song)', () async {
    final s = await resolveSeparator(
      cfg,
      isWeb: false,
      loadCrispasr: ({bool download = false}) async => null,
      loadOnnx: ({bool download = false}) async => null,
    );
    expect(s, isNull);
  });

  test('web excludes the crispasr (CLI/FFI) separator', () async {
    final s = await resolveSeparator(
      cfg,
      isWeb: true,
      loadCrispasr: ({bool download = false}) async => _fakeSep, // FFI, no web
      loadOnnx: ({bool download = false}) async => null,
    );
    expect(s, isNull);
  });

  test('an explicit onnx choice ignores an installed crispasr', () async {
    Future<Stems> onnx(Float64List m, int sr) async =>
        (vocals: m, bass: null, drums: null, other: null);

    final Separator? s = await resolveSeparator(
      cfg.copyWith(backends: {TranscriptionStep.separation: Backend.onnx}),
      isWeb: false,
      loadCrispasr: ({bool download = false}) async => _fakeSep,
      loadOnnx: ({bool download = false}) async => onnx,
    );
    expect(s, isNotNull);
    expect(identical(s, onnx), isTrue); // the onnx one, not crispasr
  });

  test('a pureDart choice → null (no pure-Dart separator)', () async {
    final s = await resolveSeparator(
      cfg.copyWith(backends: {TranscriptionStep.separation: Backend.pureDart}),
      isWeb: false,
      loadCrispasr: ({bool download = false}) async => _fakeSep,
      loadOnnx: ({bool download = false}) async => _fakeSep,
    );
    expect(s, isNull);
  });
}
