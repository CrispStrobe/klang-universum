// Downloads manager UI — lists everything CometBeat has cached on disk (AI
// models, SoundFonts, instrument samples), the total size, and a Remove action
// per category to free space (it re-downloads on next use). Works on every
// platform: native scans the on-device cache; web shows a note (no local cache).

import 'package:comet_beat/features/settings/downloads_manager.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late Future<List<DownloadCategory>> _future = scanDownloads();

  void _reload() => setState(() => _future = scanDownloads());

  Future<void> _remove(DownloadCategory c) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.downloadsRemoveConfirm(c.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.importScanCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.downloadsRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await clearDownloads(c.path);
    if (mounted) _reload();
  }

  String _fmt(int bytes) => DownloadCategory(
        id: '',
        label: '',
        bytes: bytes,
        items: 0,
        path: '',
      ).sizeLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadsTitle)),
      body: !downloadsSupported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.downloadsWebNote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : FutureBuilder<List<DownloadCategory>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final cats = snap.data!;
                if (cats.isEmpty) {
                  return Center(child: Text(l10n.downloadsEmpty));
                }
                final total = cats.fold<int>(0, (s, c) => s + c.bytes);
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        l10n.downloadsTotal(_fmt(total)),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final c in cats)
                      Card(
                        child: ListTile(
                          leading: Icon(_iconFor(c.id)),
                          title: Text(c.label),
                          subtitle: Text(
                            '${c.sizeLabel} · ${l10n.downloadsFiles(c.items)}',
                          ),
                          trailing: TextButton.icon(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(l10n.downloadsRemove),
                            onPressed: () => _remove(c),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  IconData _iconFor(String id) => switch (id) {
        'models' => Icons.smart_toy_outlined,
        'soundfonts' => Icons.piano,
        'instruments' => Icons.library_music_outlined,
        _ => Icons.folder_outlined,
      };
}
