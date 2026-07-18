// "Browse The Mod Archive" — a BYOK modal that (1) asks for the user's own API
// key if none is stored, then (2) browses the CC0/Public-Domain module subset
// and returns the picked `.mod` bytes for the Tracker to import. All the
// browse/fetch/key logic lives here (libraries-and-tab's lane); the Tracker just
// calls [showModArchiveSheet] and feeds the result to `importModuleBytes`.

import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/modarchive_key_store.dart';
import 'package:comet_beat/features/library/source_registry.dart';
import 'package:comet_beat/features/library/sources/modarchive_source.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds a ModArchive source for [key]; injectable for tests.
typedef ModArchiveSourceBuilder = ContentSource Function(String key);

ContentSource _defaultBuilder(String key) =>
    ModArchiveSource(defaultHttpGet, key);

/// Shows the ModArchive browser. Returns the picked module's raw bytes (for
/// `importModuleBytes`), or null if cancelled. Injectable [keyStore]/[builder]
/// for tests.
Future<Uint8List?> showModArchiveSheet(
  BuildContext context, {
  ModArchiveKeyStore? keyStore,
  ModArchiveSourceBuilder builder = _defaultBuilder,
}) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ModArchiveSheet(
      keyStore: keyStore ?? ModArchiveKeyStore(),
      builder: builder,
    ),
  );
}

class _ModArchiveSheet extends StatefulWidget {
  final ModArchiveKeyStore keyStore;
  final ModArchiveSourceBuilder builder;
  const _ModArchiveSheet({required this.keyStore, required this.builder});

  @override
  State<_ModArchiveSheet> createState() => _ModArchiveSheetState();
}

class _ModArchiveSheetState extends State<_ModArchiveSheet> {
  final _search = TextEditingController();
  final _keyField = TextEditingController();
  ContentSource? _source; // null until a key is present
  List<LibraryItem> _items = const [];
  bool _loading = true;
  bool _fetching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final key = await widget.keyStore.read();
    if (!mounted) return;
    if (key == null) {
      setState(() => _loading = false); // show the key form
      return;
    }
    setState(() => _source = widget.builder(key));
    await _reload();
  }

  Future<void> _saveKey() async {
    final key = _keyField.text.trim();
    if (key.isEmpty) return;
    await widget.keyStore.write(key);
    if (!mounted) return;
    setState(() => _source = widget.builder(key));
    await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _source!.browse(query: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!.libraryLoadFailed;
        _loading = false;
      });
    }
  }

  Future<void> _pick(LibraryItem item) async {
    setState(() => _fetching = true);
    try {
      final bytes = await _source!.fetch(item);
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = AppLocalizations.of(context)!.libraryImportFailed;
      });
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
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: _source != null
            ? _browser(l10n)
            : _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _keyForm(l10n),
      ),
    );
  }

  Widget _keyForm(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.modArchiveTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l10n.modArchiveKeyPrompt),
        const SizedBox(height: 8),
        TextField(
          controller: _keyField,
          decoration: InputDecoration(
            labelText: l10n.modArchiveKeyLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.modArchiveGetKey),
              onPressed: () => launchUrl(
                Uri.parse('https://modarchive.org/index.php?xml-api'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _saveKey,
              child: Text(l10n.modArchiveSaveKey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _browser(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.grid_on, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_source!.name} · ${_source!.licenseSummary}',
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
        SizedBox(height: 260, child: _list(l10n)),
      ],
    );
  }

  Widget _list(AppLocalizations l10n) {
    if (_loading || _fetching) {
      return const Center(child: CircularProgressIndicator());
    }
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
        return ListTile(
          dense: true,
          leading: const Icon(Icons.music_note),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item.composer} · ${item.declaredLicense}'),
          onTap: () => _pick(item),
        );
      },
    );
  }
}
