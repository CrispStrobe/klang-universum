// Library connector (A0) — the license gate, OpenScore path parsing, the import
// pipeline, and a widget pass over the browser. No live network: sources/http
// are faked; MusicXML is round-tripped through crisp_notation so it really
// parses.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:comet_beat/features/library/attribution_screen.dart';
import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/donation.dart';
import 'package:comet_beat/features/library/library_browser_screen.dart';
import 'package:comet_beat/features/library/library_import.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/features/library/sources/openscore_source.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fakes ────────────────────────────────────────────────────────────────
class _FakeSource implements ContentSource {
  final List<LibraryItem> items;
  final Uint8List Function() fetchBytes;
  int fetchCount = 0;
  _FakeSource(this.items, this.fetchBytes);

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake Source';
  @override
  String get homepage => 'https://example.org';
  @override
  String get licenseSummary => 'CC0 — public domain';

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final q = query.toLowerCase();
    return items
        .where(
          (i) =>
              q.isEmpty ||
              i.title.toLowerCase().contains(q) ||
              i.composer.toLowerCase().contains(q),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) async {
    fetchCount++;
    return fetchBytes();
  }
}

LibraryItem _item({
  String license = 'CC0',
  String format = 'musicxml',
  String id = 'x1',
}) =>
    LibraryItem(
      sourceId: 'fake',
      sourceName: 'Fake Source',
      id: id,
      title: 'Test Song',
      composer: 'A. Composer',
      declaredLicense: license,
      downloadUrl: Uri.parse('https://example.org/$id'),
      format: format,
      sourceUrl: 'https://example.org/work/$id',
    );

/// A minimal, really-parseable MusicXML string via a round-trip.
String _validMusicXml() =>
    scoreToMusicXml(Score.simple(notes: 'c4:q d4 e4 f4'));

Widget _wrap(Widget home, UserSongsService svc) => ChangeNotifierProvider.value(
      value: svc,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('de')],
        home: home,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LicensePolicy.classify', () {
    const p = LicensePolicy();
    test('permissive families', () {
      expect(p.classify('CC0'), LicenseKind.cc0);
      expect(p.classify('Public Domain'), LicenseKind.publicDomain);
      expect(p.classify('CC BY 4.0'), LicenseKind.ccBy);
      expect(p.classify('CC BY-SA 4.0'), LicenseKind.ccBySa);
      for (final k in [
        LicenseKind.cc0,
        LicenseKind.publicDomain,
        LicenseKind.ccBy,
        LicenseKind.ccBySa,
      ]) {
        expect(k.isPermissive, isTrue, reason: '$k');
      }
    });

    test('restrictive families are NOT read as permissive', () {
      expect(p.classify('CC BY-NC 4.0'), LicenseKind.ccByNc);
      expect(p.classify('CC BY-NC-SA'), LicenseKind.ccByNc);
      expect(p.classify('CC BY-ND'), LicenseKind.ccByNd);
      expect(p.classify('All Rights Reserved'), LicenseKind.allRightsReserved);
      expect(p.classify(''), LicenseKind.unknown);
      expect(p.classify('some weird thing'), LicenseKind.unknown);
      for (final s in ['CC BY-NC 4.0', 'CC BY-ND', 'All Rights Reserved', '']) {
        expect(p.classify(s).isPermissive, isFalse, reason: s);
      }
    });
  });

  test('gate() allows permissive, blocks the rest', () {
    const p = LicensePolicy();
    expect(p.gate(_item()), LicenseKind.cc0);
    expect(
      () => p.gate(_item(license: 'CC BY-NC 4.0')),
      throwsA(isA<LicenseBlocked>()),
    );
  });

  test('attributionFor names the work, composer and license', () {
    const p = LicensePolicy();
    final a = p.attributionFor(_item());
    expect(a, contains('Test Song'));
    expect(a, contains('A. Composer'));
    expect(a, contains('CC0'));
    expect(a, contains('Fake Source'));
  });

  group('OpenScoreSource path parsing', () {
    final lieder = OpenScoreSource.lieder((_) async => Uint8List(0));
    final quartets = OpenScoreSource.stringQuartets((_) async => Uint8List(0));

    test('parseTreePaths keeps only scores files of the given extension', () {
      const tree = '''
      {"tree": [
        {"path": "data/corpus_conversion.json"},
        {"path": "scores/Arne,_Thomas/_/Rule,_Britannia!/lc29233346.mscx"},
        {"path": "scores/Arne,_Thomas/_/Rule,_Britannia!/lc29233346.mxl"},
        {"path": "scores/Abbott,_Jane/Set_One/A_Song/lc1.mxl"}
      ]}''';
      expect(OpenScoreSource.parseTreePaths(tree, 'mxl'), hasLength(2));
      expect(OpenScoreSource.parseTreePaths(tree, 'mscx'), hasLength(1));
    });

    test('Lieder: itemForPath humanizes composer/title + builds a raw URL', () {
      final item = lieder.itemForPath(
        'scores/Arne,_Thomas/_/Rule,_Britannia!/lc29233346.mxl',
      )!;
      expect(item.composer, 'Thomas Arne');
      expect(item.title, 'Rule, Britannia!');
      expect(item.collection, '');
      expect(item.id, 'lc29233346');
      expect(item.declaredLicense, 'CC0');
      expect(item.format, 'mxl');
      expect(item.downloadUrl.host, 'raw.githubusercontent.com');
      expect(item.downloadUrl.path, contains('lc29233346.mxl'));
    });

    test('Quartets: shallower path + .mscx format parse', () {
      final item = quartets.itemForPath(
        'scores/Beach,_Amy/String_Quartet,_Op._89/sq14387632.mscx',
      )!;
      expect(item.composer, 'Amy Beach');
      expect(item.title, 'String Quartet, Op. 89');
      expect(item.id, 'sq14387632');
      expect(item.format, 'mscx');
      expect(item.downloadUrl.path, contains('OpenScore/StringQuartets/main'));
    });

    test('browse filters by query against a faked tree', () async {
      const tree = '''
      {"tree": [
        {"path": "scores/Arne,_Thomas/_/Rule,_Britannia!/lc1.mxl"},
        {"path": "scores/Schubert,_Franz/_/Ave_Maria/lc2.mxl"}
      ]}''';
      final s = OpenScoreSource.lieder((_) async => utf8.encode(tree));
      final all = await s.browse();
      expect(all, hasLength(2));
      final schubert = await s.browse(query: 'schubert');
      expect(schubert, hasLength(1));
      expect(schubert.single.composer, 'Franz Schubert');
    });
  });

  group('pipeline decodes multiple formats + donation config', () {
    final xml = _validMusicXml();

    test('bytesToMusicXml handles mscx and midi', () {
      final score = scoreFromMusicXml(xml);
      final mscx = Uint8List.fromList(utf8.encode(scoreToMscx(score)));
      final midi = scoreToMidi(score);
      // Each decodes back to a parseable MusicXML.
      expect(
        scoreFromMusicXml(bytesToMusicXml('mscx', mscx)).measures,
        isNotEmpty,
      );
      expect(
        scoreFromMusicXml(bytesToMusicXml('midi', midi)).measures,
        isNotEmpty,
      );
    });

    test('DonationConfig is off by default and needs a URL', () {
      expect(const DonationConfig().isActive, isFalse);
      expect(const DonationConfig(enabled: true).isActive, isFalse);
      expect(
        const DonationConfig(enabled: true, url: 'https://ko-fi.com/x')
            .isActive,
        isTrue,
      );
    });
  });

  group('importLibraryItem pipeline', () {
    test('permissive item → ImportedSong with provenance', () async {
      final src = _FakeSource(
        [_item()],
        () => utf8.encode(_validMusicXml()),
      );
      final song = await importLibraryItem(_item(), src);
      expect(song.title, 'Test Song');
      expect(song.attribution, contains('CC0'));
      expect(song.sourceUrl, isNotNull);
      expect(song.score.measures, isNotEmpty); // really parsed
      expect(src.fetchCount, 1);
    });

    test('non-permissive item is blocked BEFORE any fetch', () async {
      final src = _FakeSource(
        [],
        () => Uint8List(0),
      );
      await expectLater(
        importLibraryItem(_item(license: 'CC BY-NC 4.0'), src),
        throwsA(isA<LicenseBlocked>()),
      );
      expect(src.fetchCount, 0); // gate ran before fetch
    });
  });

  testWidgets('donation tile hidden by default, shown when enabled',
      (tester) async {
    final svc = UserSongsService();

    await tester.pumpWidget(_wrap(const AttributionScreen(), svc));
    await tester.pump();
    expect(find.byIcon(Icons.local_cafe), findsNothing);

    await tester.pumpWidget(
      _wrap(
        const AttributionScreen(
          donation: DonationConfig(enabled: true, url: 'https://ko-fi.com/x'),
        ),
        svc,
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.local_cafe), findsOneWidget);
  });

  testWidgets('browser lists items and imports one into the Song Book',
      (tester) async {
    final svc = UserSongsService();
    final src = _FakeSource(
      [_item()],
      () => utf8.encode(_validMusicXml()),
    );
    await tester.pumpWidget(
      _wrap(LibraryBrowserScreen(sources: [src]), svc),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(svc.songs, isEmpty);

    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();

    expect(svc.songs, hasLength(1));
    expect(svc.songs.single.attribution, contains('CC0'));
  });
}
