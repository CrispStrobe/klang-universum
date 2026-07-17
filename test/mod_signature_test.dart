// mod_reader.dart — the 4-byte signature at offset 1080 decides the channel
// count, which in turn sizes every pattern row. mod_codec_test's golden fixture
// only ever exercises 'M.K.' (4 channels), so the rest of that mapping — the
// 6/8-channel tags, the generic "%dCHN"/"%dCH" tags, and the unknown-signature
// throw — had no assertion. A regression here would silently mis-shape patterns
// for any non-4-channel module.
//
// Pure Dart: no device, no Flutter widgets.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/mod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal spec-valid `.mod` carrying [sig], with pattern data sized for
/// [channels]. Layout: 20-byte title, 31×30-byte sample descriptors, song
/// length, restart, 128-byte order table (all → pattern 0), the 4-byte
/// signature at 1080, then pattern 0 at 1084.
Uint8List _modWith(String sig, {required int channels}) {
  final b = BytesBuilder();
  void str(String s, int len) {
    final out = List<int>.filled(len, 0);
    for (var i = 0; i < s.length && i < len; i++) {
      out[i] = s.codeUnitAt(i);
    }
    b.add(out);
  }

  str('SIGTEST', 20); // title
  for (var s = 1; s <= 31; s++) {
    b.add(List<int>.filled(30, 0)); // empty sample descriptors (length 0)
  }
  b.addByte(1); // song length          (offset 950)
  b.addByte(127); // restart              (offset 951)
  b.add(List<int>.filled(128, 0)); // order table (952..1079) → pattern 0
  str(sig, 4); // signature            (1080..1083)
  b.add(List<int>.filled(64 * channels * 4, 0)); // pattern 0 (from 1084)
  return b.toBytes();
}

void main() {
  test('maps the named signature tags to their channel counts', () {
    const tags = {
      'M.K.': 4,
      'M!K!': 4,
      'M&K!': 4,
      'FLT4': 4,
      '4CHN': 4,
      '6CHN': 6,
      '8CHN': 8,
      'OCTA': 8,
      'CD81': 8,
      'FLT8': 8,
    };
    tags.forEach((sig, channels) {
      final mod = parseMod(_modWith(sig, channels: channels));
      expect(mod.channelCount, channels, reason: 'signature "$sig"');
      // The channel count must also shape every pattern row.
      expect(
        mod.patterns.first.rows.first,
        hasLength(channels),
        reason: 'row width for "$sig"',
      );
    });
  });

  test('maps the generic %dCHN and %dCH tags', () {
    expect(parseMod(_modWith('2CHN', channels: 2)).channelCount, 2);
    expect(parseMod(_modWith('16CH', channels: 16)).channelCount, 16);
    expect(parseMod(_modWith('32CH', channels: 32)).channelCount, 32);
  });

  test('throws on an unrecognized signature', () {
    expect(
      () => parseMod(_modWith('ZZZZ', channels: 4)),
      throwsA(isA<ModFormatException>()),
    );
  });
}
