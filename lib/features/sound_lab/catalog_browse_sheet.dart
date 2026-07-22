// "Browse catalog" — the Sound Library's window onto OUR curated, rights-verified
// catalog (music-db → published on Hugging Face, read via CometbeatCatalogSource).
// Lists every item with its licence + attribution, searches, and — for a
// SoundFont — downloads its bytes and hands them straight to the existing
// SoundFont preset picker (showSoundFontSheet, whose file-pick seam we inject),
// so the user auditions and chooses a preset with the code path that already
// works. The chosen instrument is returned to the host (e.g. a Tracker slot).
//
// NB: persisting a downloaded SoundFont preset into the library as a
// `soundfont_ref` needs a cached font FILE (path_provider) — a small follow-up;
// today this browses + auditions + returns for immediate use.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/soundfont_sheet.dart';
import 'package:comet_beat/features/library/source_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Opens the catalog browser. Resolves to a chosen [TrackerInstrument] (a
/// SoundFont preset), or null. [source] is injectable for tests.
Future<TrackerInstrument?> showCatalogBrowseSheet(
  BuildContext context, {
  ContentSource? source,
}) {
  return showModalBottomSheet<TrackerInstrument>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CatalogBrowseSheet(
      source: source ?? buildCatalogSources().first,
    ),
  );
}

@visibleForTesting
class CatalogBrowseSheet extends StatefulWidget {
  const CatalogBrowseSheet({required this.source, super.key});

  final ContentSource source;

  @override
  State<CatalogBrowseSheet> createState() => _CatalogBrowseSheetState();
}

class _CatalogBrowseSheetState extends State<CatalogBrowseSheet> {
  final _search = TextEditingController();
  List<LibraryItem> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.source.browse(query: _search.text.trim());
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.libraryLoadFailed;
          _loading = false;
        });
      }
    }
  }

  /// A SoundFont: download its bytes, then reuse the SoundFont preset picker
  /// (its file-pick seam fed the downloaded bytes) to audition + choose.
  Future<void> _openSoundFont(LibraryItem item) async {
    setState(() => _busy = true);
    Uint8List bytes;
    try {
      bytes = await widget.source.fetch(item);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppLocalizations.of(context)!.libraryImportFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final inst = await showSoundFontSheet(
      context,
      pick: () async => (bytes: bytes, name: item.title),
    );
    if (inst != null && mounted) Navigator.of(context).pop(inst);
  }

  void _tap(LibraryItem item) {
    final l10n = AppLocalizations.of(context)!;
    if (item.format == 'sf2' || item.format == 'sf3') {
      _openSoundFont(item);
    } else {
      // SFZ instruments (their sample tree) + modules install differently —
      // browsable here, not yet one-tap installable.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.catalogNotInstallable)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.source.name} · ${widget.source.licenseSummary}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: l10n.librarySearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            SizedBox(height: 300, child: _list(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _list(AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: Text(l10n.libraryRetry)),
          ],
        ),
      );
    }
    if (_items.isEmpty) return Center(child: Text(l10n.libraryNoResults));
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        final detail = [
          item.format.toUpperCase(),
          item.declaredLicense,
          if (item.composer.isNotEmpty) item.composer,
        ].where((s) => s.isNotEmpty).join(' · ');
        return ListTile(
          dense: true,
          leading: Icon(
            item.format == 'sf2' || item.format == 'sf3'
                ? Icons.piano
                : Icons.graphic_eq,
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: _busy ? null : () => _tap(item),
        );
      },
    );
  }
}
