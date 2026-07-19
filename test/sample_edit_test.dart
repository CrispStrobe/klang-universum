// test/sample_edit_test.dart
//
// The non-destructive PCM edit ops (TRACKER_IDEAS §B): trim, silence-strip,
// normalize, fade, reverse. Pure math over ±1 Float64List — assert values, and
// that the input is never mutated.
//
// Run: PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT \
//        flutter test test/sample_edit_test.dart

import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/sample_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('peakMagnitude', () {
    test('max abs; 0 for empty/silent', () {
      expect(
        peakMagnitude(Float64List.fromList([0.1, -0.8, 0.3])),
        closeTo(0.8, 1e-12),
      );
      expect(peakMagnitude(Float64List(0)), 0);
      expect(peakMagnitude(Float64List.fromList([0, 0, 0])), 0);
    });
  });

  group('trimPcm', () {
    final src = Float64List.fromList([0, 1, 2, 3, 4, 5]);

    test('slices [start, end); leaves the source intact', () {
      expect(trimPcm(src, 2, 4), Float64List.fromList([2, 3]));
      expect(src, Float64List.fromList([0, 1, 2, 3, 4, 5]));
    });

    test('end defaults to the length', () {
      expect(trimPcm(src, 4), Float64List.fromList([4, 5]));
    });

    test('clamps and orders out-of-range / reversed args', () {
      expect(trimPcm(src, -5, 100), src); // whole buffer
      expect(
        trimPcm(src, 4, 2),
        Float64List.fromList([2, 3]),
      ); // reversed → ordered
    });
  });

  group('trimSilence', () {
    test('strips quiet head and tail', () {
      final src = Float64List.fromList([0.001, 0.0, 0.5, -0.4, 0.002, 0.0]);
      expect(trimSilence(src), Float64List.fromList([0.5, -0.4]));
    });

    test('all-silent → empty', () {
      expect(trimSilence(Float64List.fromList([0.0, 0.001, -0.002])), isEmpty);
    });

    test('respects the threshold', () {
      final src = Float64List.fromList([0.05, 0.5, 0.05]);
      // default 0.01 keeps the 0.05 edges…
      expect(trimSilence(src).length, 3);
      // …a higher threshold strips them.
      expect(trimSilence(src, threshold: 0.1), Float64List.fromList([0.5]));
    });
  });

  group('normalizePcm', () {
    test('scales peak to target; source intact', () {
      final src = Float64List.fromList([0.25, -0.5, 0.1]);
      final out = normalizePcm(src);
      expect(peakMagnitude(out), closeTo(1.0, 1e-12));
      expect(out[1], closeTo(-1.0, 1e-12)); // the peak maps to ±target
      expect(out[0], closeTo(0.5, 1e-12)); // ratios preserved
      expect(src[1], -0.5); // unchanged
    });

    test('custom target peak', () {
      final out =
          normalizePcm(Float64List.fromList([0.2, -0.4]), targetPeak: 0.8);
      expect(peakMagnitude(out), closeTo(0.8, 1e-12));
    });

    test('silent buffer returned unchanged', () {
      expect(
        normalizePcm(Float64List.fromList([0, 0])),
        Float64List.fromList([0, 0]),
      );
    });
  });

  group('fadeIn / fadeOut', () {
    test('fadeIn ramps up from silence; source intact', () {
      final src = Float64List.fromList([1, 1, 1, 1]);
      final out = fadeIn(src, 4);
      expect(out[0], 0.0);
      expect(out[1], closeTo(0.25, 1e-12));
      expect(out[3], closeTo(0.75, 1e-12));
      expect(src[0], 1.0); // unchanged
    });

    test('fadeOut silences the last sample, mirrors fadeIn', () {
      final out = fadeOut(Float64List.fromList([1, 1, 1, 1]), 4);
      expect(out[3], 0.0);
      expect(out[2], closeTo(0.25, 1e-12));
      expect(out[0], closeTo(0.75, 1e-12));
    });

    test('fade length clamps to the buffer; 0 = identity', () {
      final src = Float64List.fromList([1, 1]);
      expect(fadeIn(src, 0), src);
      expect(() => fadeIn(src, 999), returnsNormally);
    });
  });

  group('removeDcOffset', () {
    test('subtracts the mean so the result centres on 0; source intact', () {
      final biased = Float64List.fromList([0.7, 0.3, 0.7, 0.3]); // mean 0.5
      final out = removeDcOffset(biased);
      expect(out.reduce((a, b) => a + b) / out.length, closeTo(0, 1e-12));
      expect(out[0], closeTo(0.2, 1e-12));
      expect(out[1], closeTo(-0.2, 1e-12));
      expect(biased[0], closeTo(0.7, 1e-12)); // input not mutated
    });

    test('an already-centred signal is unchanged; empty stays empty', () {
      final centred = Float64List.fromList([0.5, -0.5, 0.5, -0.5]);
      expect(removeDcOffset(centred), centred);
      expect(removeDcOffset(Float64List(0)), isEmpty);
    });
  });

  group('reversePcm', () {
    test('reverses; source intact', () {
      final src = Float64List.fromList([1, 2, 3]);
      expect(reversePcm(src), Float64List.fromList([3, 2, 1]));
      expect(src, Float64List.fromList([1, 2, 3]));
    });
  });
}
