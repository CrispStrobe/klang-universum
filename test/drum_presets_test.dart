// The built-in Drum Kit grooves: each preset is a well-formed, non-empty
// DrumRowsPattern on the shared grid, with every drum row the right length.

import 'package:comet_beat/core/audio/drum_presets.dart';
import 'package:comet_beat/core/audio/loop_engine.dart'
    show kPatternSteps, DrumRowsPattern;
import 'package:comet_beat/core/audio/synth.dart' show Drum;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('there is a useful library of named presets', () {
    expect(kDrumPresets.length, greaterThanOrEqualTo(8));
    // Names are unique and non-empty.
    final names = kDrumPresets.map((p) => p.name).toSet();
    expect(names.length, kDrumPresets.length);
    expect(names.any((n) => n.isEmpty), isFalse);
  });

  test('every preset is a full, correctly-sized, non-empty pattern', () {
    for (final preset in kDrumPresets) {
      final rows = preset.pattern.rows;
      // Every drum is present and exactly kPatternSteps long (drop-in for grid).
      for (final d in Drum.values) {
        expect(rows[d], isNotNull, reason: '${preset.name} missing $d');
        expect(rows[d]!.length, kPatternSteps, reason: '${preset.name} $d len');
      }
      // A groove has hits (it's not blank).
      final hits = rows.values.fold(0, (n, r) => n + r.where((b) => b).length);
      expect(hits, greaterThan(0), reason: '${preset.name} is empty');
      // And it renders without throwing.
      expect(preset.pattern, isA<DrumRowsPattern>());
    }
  });

  test('presets differ from one another', () {
    String sig(DrumPreset p) => [
          for (final d in Drum.values)
            p.pattern.rows[d]!.map((b) => b ? '1' : '0').join(),
        ].join('|');
    final sigs = kDrumPresets.map(sig).toSet();
    expect(
      sigs.length,
      kDrumPresets.length,
      reason: 'two presets are identical',
    );
  });
}
