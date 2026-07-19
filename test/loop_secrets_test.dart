// Secret-combo matching — pure model tests (no device).

import 'package:comet_beat/features/games/composition/loop_secrets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an exact built-in set unlocks its combo', () {
    expect(matchCombo({'drums', 'bass'})?.id, 'rhythmSection');
    expect(matchCombo({'bass', 'melody'})?.id, 'duo');
    expect(matchCombo({'drums', 'chords', 'sparkle'})?.id, 'dreamy');
    expect(
      matchCombo({'drums', 'bass', 'chords', 'melody', 'sparkle'})?.id,
      'fullBand',
    );
  });

  test('a non-matching set unlocks nothing', () {
    expect(matchCombo({}), isNull);
    expect(matchCombo({'drums'}), isNull);
    expect(matchCombo({'drums', 'bass', 'chords'}), isNull);
  });

  test('captured voice/beat layers are ignored when matching', () {
    // A rhythm-section combo still counts with a sung layer on top.
    expect(matchCombo({'drums', 'bass', 'voice'})?.id, 'rhythmSection');
    expect(matchCombo({'bass', 'melody', 'beat'})?.id, 'duo');
  });

  test('every combo is reachable and has a unique id', () {
    final ids = kLoopCombos.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'ids unique');
    for (final combo in kLoopCombos) {
      expect(matchCombo(combo.tracks)?.id, combo.id, reason: combo.id);
      expect(combo.tracks, everyElement(isIn(kComboBuiltIns)));
    }
  });
}
