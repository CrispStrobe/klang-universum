// Browses free sample PACKS (archives of many WAVs) and returns the chosen
// pack's bytes to the caller — the Sample Extractor, which already knows how
// to open .7z/.zip/.tar.* and lift the WAVs out.
//
// Distinct from `sample_library_sheet`, where one item == one WAV. Here one
// item is a whole instrument pack, so the flow is browse → download → hand the
// bytes back for extraction.

import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/source_registry.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The pack the user picked: its display name and raw archive bytes.
typedef PickedPack = ({
  String name,
  Uint8List bytes,
  String? license,
  String? sourceUrl
});

/// Shows the pack browser; resolves to the chosen pack, or null if cancelled.
Future<PickedPack?> showSamplePackSheet(
  BuildContext context, {
  List<ContentSource>? sources,
}) {
  return showModalBottomSheet<PickedPack>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SamplePackSheet(
      sources: sources ?? buildSamplePackSources(),
    ),
  );
}

class _SamplePackSheet extends StatefulWidget {
  const _SamplePackSheet({required this.sources});
  final List<ContentSource> sources;

  @override
  State<_SamplePackSheet> createState() => _SamplePackSheetState();
}

class _SamplePackSheetState extends State<_SamplePackSheet> {
  late ContentSource _source = widget.sources.first;
  final _search = TextEditingController();
  List<LibraryItem> _items = const [];
  bool _loading = false;
  String? _downloading;
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
      final items = await _source.browse(query: _search.text.trim());
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(LibraryItem item) async {
    setState(() {
      _downloading = item.id;
      _error = null;
    });
    try {
      final bytes = await _source.fetch(item);
      if (!mounted) return;
      Navigator.of(context).pop(
        (
          name: item.title,
          bytes: bytes,
          license: item.declaredLicense,
          sourceUrl: item.sourceUrl,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _downloading = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.library_music, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_source.name} · ${_source.licenseSummary}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              if (widget.sources.length > 1)
                DropdownButton<ContentSource>(
                  value: _source,
                  isExpanded: true,
                  items: [
                    for (final s in widget.sources)
                      DropdownMenuItem(value: s, child: Text(s.name)),
                  ],
                  onChanged: (s) {
                    if (s == null || s == _source) return;
                    setState(() {
                      _source = s;
                      _items = const [];
                    });
                    _reload();
                  },
                ),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _reload(),
                decoration: InputDecoration(
                  hintText: l10n.samplePackSearch,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _reload,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.samplePackHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: _items.isEmpty && !_loading
                    ? Center(child: Text(l10n.samplePackEmpty))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) {
                          final item = _items[i];
                          final busy = _downloading == item.id;
                          return ListTile(
                            leading: const Icon(Icons.folder_zip_outlined),
                            title: Text(item.title),
                            subtitle: Text(
                              '${item.declaredLicense} · ${item.format}',
                            ),
                            trailing: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download),
                            onTap:
                                _downloading != null ? null : () => _pick(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
