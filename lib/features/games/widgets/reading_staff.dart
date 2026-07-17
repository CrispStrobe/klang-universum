// lib/features/games/widgets/reading_staff.dart
//
// A StaffView that honours the app-wide "note names under the staff" reading
// scaffold (SettingsService.showNoteNames), spelled per the note-naming setting.
//
// Use it in games where naming the note is NOT the task (rhythm, articulation,
// beaming, playing). The note-naming quizzes build StaffView directly, so the
// scaffold never prints — and reveals — their answer.
//
// StaffView spells the names as international letters (C…B); per-locale spelling
// (German H, solfège) would need a `noteNameStyle` param on StaffView in
// crisp_notation (MultiSystemView already has one) — a small follow-up.

import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

class ReadingStaffView extends StatelessWidget {
  const ReadingStaffView({
    super.key,
    required this.score,
    this.staffSpace = 18,
    this.theme,
  });

  final Score score;
  final double staffSpace;

  /// Defaults to [kidsScoreTheme] (the games' theme) when omitted.
  final CrispNotationTheme? theme;

  @override
  Widget build(BuildContext context) {
    return StaffView(
      score: score,
      staffSpace: staffSpace,
      theme: theme ?? kidsScoreTheme,
      showNoteNames: context.watch<SettingsService>().showNoteNames,
    );
  }
}
