// lib/features/curriculum/screens/curriculum_screen.dart
//
// Lists the curricula (the Leistungsabzeichen badges, and a general school-music
// guide). Each shows its levels with a readiness bar derived from the child's
// stars in the mapped games; tapping a level opens its topic breakdown.

import 'package:flutter/material.dart';
import 'package:klang_universum/core/curriculum/curriculum.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/features/curriculum/screens/curriculum_level_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class CurriculumScreen extends StatelessWidget {
  const CurriculumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = context.watch<ProgressService>();
    int stars(String id) => progress.starsFor(id);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.curriculumTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final curriculum in kCurricula) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  curriculum.name(l10n),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final level in curriculum.levels)
                _LevelCard(
                  level: level,
                  readiness: levelReadiness(level, stars),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CurriculumLevelScreen(level: level),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.curGuideNote,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.readiness,
    required this.onTap,
  });

  final CurriculumLevel level;
  final double readiness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pct = (readiness * 100).round();
    return Card(
      child: ListTile(
        leading: Text(level.badge, style: const TextStyle(fontSize: 30)),
        title: Text(level.name(l10n)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: readiness,
                  minHeight: 7,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.curReadiness(pct),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
