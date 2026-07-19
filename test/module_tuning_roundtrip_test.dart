// Sample-tuning round-trip matrix across the four module formats. Pins how a
// sample's c5speed (its playback rate at the C-5 reference) survives
// `doc → convertTo<Fmt> → parseAnyModule`, which each format stores very
// differently:
//   * S3M (c2spd) and IT (c5speed) carry the full rate exactly.
//   * XM stores relative-note + a signed finetune, so an arbitrary rate
//     round-trips within a tiny (~0.1%) quantization error.
//   * ProTracker MOD has ONLY a 4-bit finetune nudge around the fixed 8363-Hz
//     C-5 reference, so it can carry that reference rate exactly but NOT an
//     arbitrary sample rate — a far rate collapses back toward 8363.
//
// None of this is a bug: it's the inherent tuning resolution of each format.
// The matrix documents and locks it (a change would fail loudly) in the
// crisp_notation round-trip matrix's `droppedBy` spirit. Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _emptyRow = <DocCell>[DocCell.empty];

/// The fixed C-5 reference rate a ProTracker `.mod` sample plays at (finetune 0).
const _kModReferenceC5 = 8363;

/// Formats that store the full sample rate and round-trip it exactly.
const _exactFormats = {ModuleFormat.s3m, ModuleFormat.it};

ModuleDoc docWithC5(int c5speed) {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.it,
    order: [0],
    patterns: const [
      DocPattern([_emptyRow], 1),
    ],
    samples: [DocSample(pcm: pcm, c5speed: c5speed)],
  );
}

int _c5After(int c5, ModuleFormat fmt) =>
    parseAnyModule(convertDocTo(docWithC5(c5), fmt)).usedSamples.first.c5speed;

void main() {
  group('sample-tuning round-trip matrix (doc → write → parse)', () {
    test('the 8363 C-5 reference rate survives every format exactly', () {
      for (final fmt in ModuleFormat.values) {
        expect(
          _c5After(_kModReferenceC5, fmt),
          _kModReferenceC5,
          reason: '${fmt.name} must keep the reference rate',
        );
      }
    });

    for (final c5 in const [22050, 44100]) {
      test('an arbitrary rate ($c5): S3M/IT exact · XM near · MOD collapses',
          () {
        // S3M + IT carry the full rate exactly.
        for (final fmt in _exactFormats) {
          expect(_c5After(c5, fmt), c5, reason: '${fmt.name} exact');
        }
        // XM's relative-note + finetune round-trips within ~0.1%.
        expect(_c5After(c5, ModuleFormat.xm), closeTo(c5, c5 * 0.001));
        // MOD has only a ±finetune nudge around 8363, so a far rate cannot be
        // represented — it collapses well below the requested rate.
        expect(
          _c5After(c5, ModuleFormat.mod),
          lessThan(c5 ~/ 2),
          reason: 'MOD cannot carry an arbitrary sample rate',
        );
      });
    }

    test('MOD is the only format that cannot carry an arbitrary rate', () {
      const c5 = 44100;
      final lossless = <String>[];
      for (final fmt in ModuleFormat.values) {
        // "Carries it" = within XM's tolerance (exact for S3M/IT/reference).
        if ((_c5After(c5, fmt) - c5).abs() <= c5 * 0.001) {
          lossless.add(fmt.name);
        }
      }
      expect(lossless..sort(), ['it', 's3m', 'xm']);
    });
  });
}
