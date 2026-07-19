// lib/features/games/composition/loop_challenges.dart
//
// Band challenges (Loop Mixer §E-2): zero-pressure, no-score prompts that nudge
// a kid to explore ("add something sparkly", "stack three layers"). Each is a
// pure predicate over the currently-enabled track ids, so the screen can tell
// when one is met and gently move on — matching the app's no-fail stance.

/// Whether a challenge is satisfied by the set of enabled track ids.
typedef ChallengeCheck = bool Function(Set<String> enabled);

/// One prompt: a stable [id] (for the localized text) + its [check].
class BandChallenge {
  const BandChallenge(this.id, this.check);
  final String id;
  final ChallengeCheck check;
}

bool _hasSparkle(Set<String> e) => e.contains('sparkle');
bool _hasBass(Set<String> e) => e.contains('bass');
bool _hasMelody(Set<String> e) => e.contains('melody') || e.contains('chords');
bool _threeLayers(Set<String> e) => e.length >= 3;
bool _fullBand(Set<String> e) =>
    e.containsAll(const {'drums', 'bass', 'melody'});

/// The offered challenges, in order. Ids are stable (they key the l10n prompt).
const List<BandChallenge> kBandChallenges = [
  BandChallenge('sparkle', _hasSparkle),
  BandChallenge('bass', _hasBass),
  BandChallenge('melody', _hasMelody),
  BandChallenge('layers', _threeLayers),
  BandChallenge('fullBand', _fullBand),
];
