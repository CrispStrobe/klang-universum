// The "Browse catalog" sheet renders OUR curated HF catalog: title, licence,
// and attribution per item, searchable, driven by an injected ContentSource
// (no network). A SoundFont shows the piano icon (its tap opens the preset
// picker); non-SoundFonts are browsable but not yet one-tap installable.

import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/sound_lab/catalog_browse_sheet.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake in-memory catalog source.
class _FakeSource implements ContentSource {
  _FakeSource(this._items);
  final List<LibraryItem> _items;

  @override
  String get id => 'fake';
  @override
  String get name => 'CometBeat Library';
  @override
  String get homepage => 'https://example';
  @override
  String get licenseSummary => 'CC0 / CC-BY / PD';

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final q = query.trim().toLowerCase();
    return q.isEmpty
        ? _items
        : _items.where((i) => i.title.toLowerCase().contains(q)).toList();
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) async => Uint8List(0);
}

LibraryItem _item(String title, String fmt, String lic, String attr) =>
    LibraryItem(
      sourceId: 'fake',
      sourceName: 'CometBeat Library',
      id: title,
      title: title,
      composer: attr,
      collection: fmt == 'sf2' ? 'soundfont' : 'instrument',
      declaredLicense: lic,
      downloadUrl: Uri.parse('https://h/$title'),
      format: fmt,
    );

Widget _host(ContentSource src) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CatalogBrowseSheet(source: src)),
    );

void main() {
  testWidgets('lists catalog items with licence + attribution', (tester) async {
    final src = _FakeSource([
      _item('FluidR3 GM', 'sf2', 'MIT License', 'Frank Wen'),
      _item('Cello VCSL', 'sfz', 'CC0', 'Versilian'),
    ]);
    await tester.pumpWidget(_host(src));
    await tester.pumpAndSettle();

    expect(find.text('FluidR3 GM'), findsOneWidget);
    expect(find.text('Cello VCSL'), findsOneWidget);
    // detail line carries format · licence · attribution
    expect(find.textContaining('MIT License'), findsOneWidget);
    expect(find.textContaining('Frank Wen'), findsOneWidget);
    // SoundFont gets the piano icon; the SFZ gets the waveform icon
    expect(find.byIcon(Icons.piano), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
  });

  testWidgets('search narrows the list', (tester) async {
    final src = _FakeSource([
      _item('FluidR3 GM', 'sf2', 'MIT License', 'Frank Wen'),
      _item('Cello VCSL', 'sfz', 'CC0', 'Versilian'),
    ]);
    await tester.pumpWidget(_host(src));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'fluid');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('FluidR3 GM'), findsOneWidget);
    expect(find.text('Cello VCSL'), findsNothing);
  });
}
