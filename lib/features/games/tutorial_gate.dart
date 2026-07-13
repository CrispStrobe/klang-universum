// lib/features/games/tutorial_gate.dart
//
// Bridges the registry's per-game [GameInfo.tutorial] to the tutorial UI without
// touching individual game screens: [gameRoute] wraps a game in a [TutorialGate]
// that auto-shows its tutorial the first time the game is opened (afterwards
// it's silent; reopen via the "?" button). Every game-launch site pushes
// gameRoute(game) instead of MaterialPageRoute(builder: game.builder).

import 'package:flutter/material.dart';
import 'package:klang_universum/features/games/game_registry.dart';
import 'package:klang_universum/shared/tutorial/tutorial_sheet.dart';

/// A route to [game] that auto-shows its tutorial (if any) on the first visit.
Route<void> gameRoute(GameInfo game) =>
    MaterialPageRoute<void>(builder: (_) => TutorialGate(game: game));

/// Renders [GameInfo.builder] and, on the first frame of the first-ever visit,
/// pops up the game's tutorial. A transparent passthrough otherwise.
class TutorialGate extends StatefulWidget {
  const TutorialGate({super.key, required this.game});
  final GameInfo game;

  @override
  State<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends State<TutorialGate> {
  @override
  void initState() {
    super.initState();
    final tutorial = widget.game.tutorial;
    if (tutorial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowTutorial(context, widget.game.id, tutorial);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.game.builder(context);
}
