// Route a symbolic score to the editors. Any [MultiPartScore] — imported from the
// library/music picker, transcribed, or lifted out of an Audio Editor music clip
// — can be opened in the Score Workshop or the Tab Workshop from one place. The
// "and back" half already exists: each editor has "Send to Audio Editor"
// (sendToMultitrack), so imported symbolic music round-trips between the library,
// the Audio Editor and the editors.

import 'package:comet_beat/features/games/composition/tab_workshop_screen.dart'
    show TabWorkshopScreen;
import 'package:comet_beat/features/workshop/screens/composition_workshop_screen.dart'
    show CompositionWorkshopScreen;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart'
    show MultiPartScore;
import 'package:flutter/material.dart';

/// Open [score] in the full Score Workshop (editable notation, all parts).
void openScoreInWorkshop(
  BuildContext context,
  MultiPartScore score, {
  List<String>? names,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CompositionWorkshopScreen(
        initialScore: score,
        initialNames: names,
      ),
    ),
  );
}

/// Open [score] in the Tab Workshop — one editable tab track per part, so a
/// multi-instrument score keeps every instrument (no-op on an empty score).
void openScoreInTab(
  BuildContext context,
  MultiPartScore score, {
  List<String>? names,
}) {
  if (score.parts.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          TabWorkshopScreen(initialParts: score, initialNames: names),
    ),
  );
}

/// A bottom sheet that lets the user open [score] in a chosen editor (Score
/// Workshop or Tab Workshop). Pops itself, then pushes the editor.
Future<void> showScoreDestinations(
  BuildContext context,
  MultiPartScore score, {
  List<String>? names,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.open_in_new, size: 20),
                const SizedBox(width: 8),
                Text(
                  l10n.scoreRouterTitle,
                  style: Theme.of(sheetCtx).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(l10n.workshopModeScore),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              openScoreInWorkshop(context, score, names: names);
            },
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: Text(l10n.workshopModeTab),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              openScoreInTab(context, score, names: names);
            },
          ),
        ],
      ),
    ),
  );
}
