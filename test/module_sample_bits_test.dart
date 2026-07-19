// Sample bit-depth round-trip: XM and IT can store 16-bit samples, and their
// readers already decode them — but doc→module always built 8-bit samples, so a
// full-precision waveform lost ~8 bits on export. DocSample.sixteenBit (default
// false = classic 8-bit, byte-identical) now opts a sample into 16-bit for the
// formats that support it. This pins that:
//   * a 16-bit XM/IT export reconstructs the waveform far tighter than 8-bit,
//   * the 16-bit flag survives import (docFromXm/docFromIt) → re-export, and
//   * MOD (8-bit only) ignores the flag.
// moduleDocFromSong opts its samples into 16-bit so recorded/rendered app audio
// keeps its quality on XM/IT export. Pure Dart.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _emptyRow = <DocCell>[DocCell.empty];

Float64List _sine() {
  final pcm = Float64List(256);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.9 * sin(2 * pi * 4 * i / pcm.length);
  }
  return pcm;
}

ModuleDoc _docWith({required bool sixteenBit}) => ModuleDoc(
      channelCount: 1,
      sourceFormat: ModuleFormat.it,
      order: [0],
      patterns: const [
        DocPattern([_emptyRow], 1),
      ],
      samples: [
        DocSample(pcm: _sine(), c5speed: 44100, sixteenBit: sixteenBit),
      ],
    );

double _maxErr(Float64List a, Float64List b) {
  var m = 0.0;
  final n = min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    final e = (a[i] - b[i]).abs();
    if (e > m) m = e;
  }
  return m;
}

double _errAfter(ModuleFormat fmt, {required bool sixteenBit}) {
  final back =
      parseAnyModule(convertDocTo(_docWith(sixteenBit: sixteenBit), fmt));
  return _maxErr(_sine(), back.usedSamples.first.pcm);
}

void main() {
  group('sample bit-depth round-trip', () {
    for (final fmt in const [ModuleFormat.xm, ModuleFormat.it]) {
      test('${fmt.name}: 16-bit reconstructs far tighter than 8-bit', () {
        final err16 = _errAfter(fmt, sixteenBit: true);
        final err8 = _errAfter(fmt, sixteenBit: false);
        expect(err8, greaterThan(0.002)); // 8-bit quantization is coarse
        expect(err16, lessThan(0.0005)); // 16-bit is near-lossless
        expect(err16, lessThan(err8 / 4)); // a clear improvement
      });

      test('${fmt.name}: the 16-bit flag survives import → re-export', () {
        final back =
            parseAnyModule(convertDocTo(_docWith(sixteenBit: true), fmt));
        expect(back.usedSamples.first.sixteenBit, isTrue);
        // Re-exporting the imported 16-bit doc stays 16-bit (tight).
        final err = _maxErr(
          _sine(),
          parseAnyModule(convertDocTo(back, fmt)).usedSamples.first.pcm,
        );
        expect(err, lessThan(0.0005));
      });
    }

    test('MOD ignores the 16-bit flag (8-bit format)', () {
      // Even with sixteenBit true, MOD stores 8-bit → coarse either way.
      expect(_errAfter(ModuleFormat.mod, sixteenBit: true), greaterThan(0.002));
    });

    test('the default sample stays 8-bit (byte-identical export path)', () {
      final back = parseAnyModule(convertToXm(_docWith(sixteenBit: false)));
      expect(back.usedSamples.first.sixteenBit, isFalse);
    });
  });
}
