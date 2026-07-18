// "Sources & credits" — lists the provenance of every work imported from an
// external open-music library, so attribution travels with the app. Tapping a
// credit opens its source URL. Fulfils the compliance-checklist requirement in
// docs/LIBRARIES_AND_TAB_SCOPING.md §1.7.

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/donation.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AttributionScreen extends StatelessWidget {
  /// Donation config for the optional "Support the developer" tile (off by
  /// default). Injectable for tests.
  final DonationConfig donation;

  const AttributionScreen({super.key, this.donation = kDonation});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = context.watch<UserSongsService>();
    final credited = service.songs.where((s) => s.attribution != null).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.librarySourcesCredits)),
      bottomNavigationBar: donation.isActive
          ? SafeArea(
              child: ListTile(
                leading: const Icon(Icons.local_cafe),
                title: Text(l10n.librarySupportDev),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => launchUrl(
                  Uri.parse(donation.url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            )
          : null,
      body: credited.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.libraryNoCredits,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l10n.libraryCreditsIntro,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                for (final song in credited)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text(song.attribution!),
                      trailing: song.sourceUrl == null
                          ? null
                          : const Icon(Icons.open_in_new, size: 18),
                      onTap: song.sourceUrl == null
                          ? null
                          : () => launchUrl(
                                Uri.parse(song.sourceUrl!),
                                mode: LaunchMode.externalApplication,
                              ),
                    ),
                  ),
              ],
            ),
    );
  }
}
