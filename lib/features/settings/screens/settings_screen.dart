// lib/features/settings/screens/settings_screen.dart
//
// Language override (system/EN/DE) and a compact SRI statistics summary.

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:klang_universum/core/audio/synth.dart' show Instrument;
import 'package:klang_universum/core/note_naming.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/custom_licenses_registry.dart';
import 'package:klang_universum/core/services/debug_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/note_reading/note_colors.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:partitura/partitura.dart';
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
            l10n.instrumentLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final instrument in Instrument.values)
                    ChoiceChip(
                      avatar: Icon(_instrumentIcon(instrument)),
                      label: Text(_instrumentName(l10n, instrument)),
                      selected: settings.instrument == instrument,
                      onSelected: (_) {
                        settings.setInstrument(instrument);
                        // Preview the voice right away.
                        context.read<AudioService>()
                          ..instrument = instrument
                          ..playMidiNote(67);
                      },
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
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l10n.colorScaffoldLabel),
                  subtitle: Text(l10n.colorScaffoldSubtitle),
                  value: settings.colorScaffold,
                  onChanged: settings.setColorScaffold,
                ),
                if (settings.colorScaffold)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final step in Step.values)
                          Column(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: pitchClassColor(step),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                noteNameFor(context, step),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (context.watch<DebugService>().menuEnabled) ...[
            const SizedBox(height: 20),
            Text(
              l10n.debugSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.lock_open),
                title: Text(l10n.debugUnlockLabel),
                value: context.watch<DebugService>().unlockAll,
                onChanged: (v) => context.read<DebugService>().setUnlockAll(v),
              ),
            ),
          ],
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
          Text(
            l10n.aboutTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.appTitle),
              subtitle: Text(l10n.aboutSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAbout(context, l10n),
            ),
          ),
          const SizedBox(height: 16),
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

  /// The standard Flutter About dialog — app name, version, legalese, and a
  /// built-in "View licenses" button that opens showLicensePage. We register
  /// the bundled Bravura (OFL) font license first so it shows there alongside
  /// the auto-discovered pub-package licenses.
  Future<void> _showAbout(BuildContext context, AppLocalizations l10n) async {
    final info = await PackageInfo.fromPlatform();
    await ensureCustomLicensesRegistered();
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: l10n.appTitle,
      applicationVersion: '${info.version}+${info.buildNumber}',
      applicationLegalese: l10n.appLegalese,
      applicationIcon: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.music_note, size: 40),
      ),
    );
  }
}

IconData _instrumentIcon(Instrument instrument) => switch (instrument) {
      Instrument.piano => Icons.piano,
      Instrument.cello => Icons.music_note,
      Instrument.flute => Icons.air,
      Instrument.musicBox => Icons.toys,
    };

String _instrumentName(AppLocalizations l10n, Instrument instrument) =>
    switch (instrument) {
      Instrument.piano => l10n.instrumentPiano,
      Instrument.cello => l10n.instrumentCello,
      Instrument.flute => l10n.instrumentFlute,
      Instrument.musicBox => l10n.instrumentMusicBox,
    };
