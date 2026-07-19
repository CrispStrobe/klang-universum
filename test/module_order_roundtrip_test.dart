// Order-list round-trip matrix across the four module formats. The order list
// (the play sequence of pattern indices, which may REPEAT a pattern) is the
// arrangement backbone of a module; this pins that it survives
// `doc → convertTo<Fmt> → parseAnyModule` for MOD / S3M / XM / IT — both the
// sequence itself and the identity of the pattern each slot points at (a note
// planted in each pattern is followed through the round-trip).
//
// All four formats carry a repeating order faithfully — no `droppedBy` here —
// so every cell is a regression lock. Formats store the order differently (MOD:
// length + array; S3M/IT: array with 0xFF/0xFE end markers; XM: patternOrder),
// which is exactly why a cross-format lock is worth having. Pure Dart.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-row, one-channel pattern whose single cell plays [note] — a marker so
/// the order sequence is identifiable after a round-trip.
DocPattern _patWithNote(int note) => DocPattern(
      [
        [DocCell(note: note, instrument: 1)],
      ],
      1,
    );

ModuleDoc docWithOrder(List<int> order) {
  final pcm = Float64List(32);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (i % 8 < 4) ? 0.5 : -0.5;
  }
  return ModuleDoc(
    channelCount: 1,
    sourceFormat: ModuleFormat.it,
    order: order,
    patterns: [_patWithNote(60), _patWithNote(72)],
    samples: [DocSample(pcm: pcm, c5speed: 44100)],
  );
}

/// The note planted in each pattern the round-tripped [order] points at — the
/// arrangement as actually heard.
List<int> _noteSequence(ModuleDoc doc) => [
      for (final oi in doc.order)
        if (oi >= 0 && oi < doc.patterns.length)
          doc.patterns[oi].rows.first.first.note
        else
          -1,
    ];

void main() {
  group('order-list round-trip matrix (doc → write → parse)', () {
    for (final fmt in ModuleFormat.values) {
      group(fmt.name, () {
        test('a repeating order [0,1,0,1,0] round-trips as-heard', () {
          const order = [0, 1, 0, 1, 0];
          final back = parseAnyModule(convertDocTo(docWithOrder(order), fmt));
          expect(back.order.length, order.length);
          expect(_noteSequence(back), [60, 72, 60, 72, 60]);
        });

        test('an order not starting at pattern 0 keeps its sequence', () {
          const order = [1, 0, 1];
          final back = parseAnyModule(convertDocTo(docWithOrder(order), fmt));
          expect(_noteSequence(back), [72, 60, 72]);
        });
      });
    }

    test('every format preserves the played arrangement', () {
      const order = [0, 1, 1, 0];
      final dropped = <String>[];
      for (final fmt in ModuleFormat.values) {
        final back = parseAnyModule(convertDocTo(docWithOrder(order), fmt));
        if (_noteSequence(back).join(',') != '60,72,72,60') {
          dropped.add(fmt.name);
        }
      }
      expect(dropped, isEmpty);
    });
  });
}
