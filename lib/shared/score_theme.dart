// lib/shared/score_theme.dart
//
// The music (SMuFL) font used for all rendered notation, switchable by the
// "Handwritten notes" setting: Bravura (the default, bundled by partitura) or
// Petaluma (a jazz / handwritten face, SIL OFL 1.1, bundled by this app under
// assets/smufl/).
//
// Exposed as a no-arg getter so every StaffView / MultiSystemView site can use
// `kidsScoreTheme` in place of the const `PartituraTheme.kids` without threading
// a BuildContext. SettingsService mutates [appScoreFont] when the toggle flips;
// screens entered afterwards pick up the new font (games are pushed fresh).

import 'package:partitura/partitura.dart';

/// This app's bundled Petaluma face (SIL OFL 1.1). `package` is null, so the
/// family + metadata resolve from the app's own bundle (declared in pubspec).
const MusicFont kPetalumaFont = MusicFont(
  family: 'Petaluma',
  metadataAsset: 'assets/smufl/petaluma_metadata.json',
);

/// The notation font currently in effect. Set by [SettingsService].
MusicFont appScoreFont = MusicFont.bravura;

/// The kids theme with the selected music font applied. Stays the shared const
/// for the default (Bravura) so nothing changes when the toggle is off.
PartituraTheme get kidsScoreTheme => appScoreFont == MusicFont.bravura
    ? PartituraTheme.kids
    : PartituraTheme.kids.copyWith(musicFont: appScoreFont);
