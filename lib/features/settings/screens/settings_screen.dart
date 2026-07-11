// lib/features/settings/screens/settings_screen.dart
//
// Language override (system/EN/DE) and a compact SRI statistics summary.

import 'package:flutter/material.dart';
import 'package:klang_universum/core/note_naming.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final sri = context.watch<SriService>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.languageLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: RadioGroup<String>(
              groupValue: settings.locale?.languageCode ?? '',
              onChanged: (code) => settings.setLocale(
                (code == null || code.isEmpty) ? null : Locale(code),
              ),
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: Text(l10n.systemDefault),
                    value: '',
                  ),
                  const RadioListTile<String>(
                    title: Text('English'),
                    value: 'en',
                  ),
                  const RadioListTile<String>(
                    title: Text('Deutsch'),
                    value: 'de',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.noteNamingLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: RadioGroup<NoteNaming>(
              groupValue: settings.noteNaming,
              onChanged: (naming) =>
                  settings.setNoteNaming(naming ?? NoteNaming.auto),
              child: Column(
                children: [
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingAuto),
                    value: NoteNaming.auto,
                  ),
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingGerman),
                    value: NoteNaming.germanH,
                  ),
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingEnglish),
                    value: NoteNaming.english,
                  ),
                  RadioListTile<NoteNaming>(
                    title: Text(l10n.noteNamingSolfege),
                    value: NoteNaming.solfege,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              title: Text(l10n.showTimerLabel),
              value: settings.showTimer,
              onChanged: settings.setShowTimer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.statsTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dataset),
                  title: Text(l10n.statsTracked),
                  trailing: Text('${sri.totalTrackedItems}'),
                ),
                ListTile(
                  leading: const Icon(Icons.school),
                  title: Text(l10n.statsLearning),
                  trailing: Text('${sri.learningItemCount}'),
                ),
                ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: Text(l10n.boxMastered),
                  trailing: Text('${sri.masteredItemCount}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              return Text(
                info == null
                    ? ''
                    : 'KlangUniversum ${info.version}+${info.buildNumber}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              );
            },
          ),
        ],
      ),
    );
  }
}
