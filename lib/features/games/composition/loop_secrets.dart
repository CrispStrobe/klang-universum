// lib/features/games/composition/loop_secrets.dart
//
// Secret combos for the Loop Mixer: certain sets of enabled built-in layers
// unlock a named "combo", turning the open sandbox into a little discovery
// game ("which layers hide a secret?"). Pure + Flutter-free so it unit-tests
// without a device; the screen shows a reveal + a found N/M counter.

/// One secret combo: a stable [id] (used for l10n + the found-set) and the
/// exact set of built-in layers that unlocks it.
class LoopCombo {
  const LoopCombo(this.id, this.tracks);

  final String id;
  final Set<String> tracks;
}

/// The built-in layers a combo is matched over — captured voice/beat layers are
/// ignored, so singing over a combo never hides it.
const kComboBuiltIns = {'drums', 'bass', 'chords', 'melody', 'sparkle'};

/// The offered secret combos. Kept small and hand-authored so each is a real
/// "aha" rather than noise; every one sounds good (all content is one
/// pentatonic). Ordered most-reachable first.
const kLoopCombos = <LoopCombo>[
  LoopCombo('rhythmSection', {'drums', 'bass'}),
  LoopCombo('duo', {'bass', 'melody'}),
  LoopCombo('dreamy', {'drums', 'chords', 'sparkle'}),
  LoopCombo('marching', {'drums', 'bass', 'melody'}),
  LoopCombo('fullBand', {'drums', 'bass', 'chords', 'melody', 'sparkle'}),
];

/// The secret combo the [enabled] set matches, or null. Matched on the built-in
/// layers only (an exact match, so it stays a real puzzle): the enabled
/// built-ins must equal a combo's set exactly.
LoopCombo? matchCombo(Set<String> enabled) {
  final core = enabled.where(kComboBuiltIns.contains).toSet();
  for (final combo in kLoopCombos) {
    if (core.length == combo.tracks.length && core.containsAll(combo.tracks)) {
      return combo;
    }
  }
  return null;
}
