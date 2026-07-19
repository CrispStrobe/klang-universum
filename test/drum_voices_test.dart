// The percussion palette: every Drum voice (the 3 classics + the 5 extended
// kit voices) renders a non-silent, unit-peak one-shot, and the new voices are
// distinct from each other and from the originals.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double peak(Float64List b) =>
      b.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);

  group('drum voices', () {
    test('every Drum renders a non-silent, unit-peak hit', () {
      for (final d in Drum.values) {
        final buf = renderDrum(d);
        expect(buf, isNotEmpty, reason: '$d empty');
        expect(peak(buf), closeTo(1.0, 1e-9), reason: '$d not unit-peak');
        expect(buf.any((v) => v != 0), isTrue, reason: '$d silent');
      }
    });

    test('the kit has 8 voices (3 classic + 5 extended)', () {
      expect(Drum.values.length, 8);
      // The classic three keep their positions (index/order is stable).
      expect(Drum.values[0], Drum.kick);
      expect(Drum.values[1], Drum.snare);
      expect(Drum.values[2], Drum.hat);
      // The new voices are present.
      for (final d in [
        Drum.openHat,
        Drum.clap,
        Drum.tom,
        Drum.rim,
        Drum.cowbell,
      ]) {
        expect(Drum.values.contains(d), isTrue);
      }
    });

    test('each new voice is distinct from the others (length or content)', () {
      final voices = {for (final d in Drum.values) d: renderDrum(d)};
      // Every pair differs — either a different duration or clearly different
      // samples over the shared span (no two voices are the same buffer).
      final list = Drum.values;
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = voices[list[i]]!, b = voices[list[j]]!;
          var same = a.length == b.length;
          if (same) {
            for (var k = 0; k < a.length; k++) {
              if ((a[k] - b[k]).abs() > 1e-6) {
                same = false;
                break;
              }
            }
          }
          expect(same, isFalse, reason: '${list[i]} == ${list[j]}');
        }
      }
    });

    test('open hat rings longer than the closed hat', () {
      // The defining difference: a much longer tail.
      expect(renderDrum(Drum.openHat).length,
          greaterThan(renderDrum(Drum.hat).length * 3));
    });
  });
}
