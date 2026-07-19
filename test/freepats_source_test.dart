// Freepats source — licence resolution, the ambiguity guard, download-variant
// selection, and gating. Driven by REAL page HTML saved under
// test/fixtures/freepats (no network).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';
import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/features/library/sample_pack_sheet.dart';
import 'package:comet_beat/features/library/sources/freepats_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

String _page(String name) =>
    File('test/fixtures/freepats/$name.html').readAsStringSync();

void main() {
  final guitar = _page('Guitar_acoustic-guitar'); // CC0 only
  final piano = _page('Piano_acoustic-grand-piano'); // CC BY 3.0 *and* CC0
  final drums = _page('Percussion_acoustic-drum-kit'); // CC BY 4.0 only
  final gm = _page('SoundSets_general-midi'); // no licence statement

  group('licence resolution', () {
    test('a single-licence page resolves to that licence', () {
      final license = freepatsLicenseFrom(guitar);
      expect(const LicensePolicy().classify(license), LicenseKind.cc0);
    });

    test('a page declaring TWO licences is reported ambiguous, not guessed',
        () {
      // The grand-piano page carries both CC BY 3.0 and CC0 downloads —
      // attributing either one to a specific file would be a mislabel.
      final license = freepatsLicenseFrom(piano);
      expect(license, kFreepatsAmbiguous);
      // …and the gate must therefore reject it.
      expect(
        const LicensePolicy().classify(license),
        LicenseKind.unknown,
      );
    });

    test('a CC BY page resolves to CC BY (blocked by default, opt-in allows)',
        () {
      final license = freepatsLicenseFrom(drums);
      const policy = LicensePolicy();
      expect(policy.classify(license), LicenseKind.ccBy);
      expect(policy.allows(LicenseKind.ccBy), isFalse); // default = CC0/PD only
      expect(
        const LicensePolicy(allowAttributionLicenses: true)
            .allows(LicenseKind.ccBy),
        isTrue,
      );
    });

    test('a page with no licence statement yields nothing usable', () {
      expect(freepatsLicenseFrom(gm), isEmpty);
    });
  });

  group('download selection', () {
    test('prefers the plain SFZ (WAV) archive over FLAC and SF2 variants', () {
      final href = freepatsDownloadFrom(guitar)!;
      expect(href, endsWith('.7z'));
      expect(href.toLowerCase(), contains('sfz'));
      expect(href.toLowerCase(), isNot(contains('flac'))); // we can't decode it
      expect(href.toLowerCase(), isNot(contains('sf2')));
    });

    test('returns null when a page offers no archive', () {
      expect(freepatsDownloadFrom('<html><body>nothing</body></html>'), isNull);
    });

    // Freepats packaging is NOT uniform: most instruments ship .7z, but the
    // kalimba ships .tar.xz. Matching only .7z silently hid it from browsing.
    test('finds a .tar.xz pack, not just .7z', () {
      final kalimba = _page('Ethnic_kalimba');
      final href = freepatsDownloadFrom(kalimba)!;
      expect(href, endsWith('.tar.xz'));
      expect(href.toLowerCase(), contains('sfz')); // WAV variant, not SF2
      expect(freepatsFormatOf(href), 'tar.xz');
    });

    test('reports the container format it picked', () {
      expect(freepatsFormatOf('X/Y-SFZ-2019.7z'), '7z');
      expect(freepatsFormatOf('X/Y-SFZ-2019.tar.gz'), 'tar.gz');
      expect(freepatsFormatOf('X/Y.weird'), 'archive');
    });
  });

  test('titles read from the page path', () {
    expect(
      freepatsTitleFrom('Guitar/steel-acoustic-guitar.html'),
      'Steel Acoustic Guitar',
    );
  });

  group('browse / fetch', () {
    test('surfaces CC0 instruments and hides ambiguous / CC BY ones', () async {
      final served = {
        'Guitar/acoustic-guitar.html': guitar,
        'Piano/acoustic-grand-piano.html': piano,
        'Percussion/acoustic-drum-kit.html': drums,
      };
      Future<Uint8List> http(Uri url) async {
        for (final entry in served.entries) {
          if (url.toString().endsWith(entry.key)) {
            return Uint8List.fromList(utf8.encode(entry.value));
          }
        }
        return Uint8List.fromList(utf8.encode('<html></html>'));
      }

      final src = FreepatsSource(http);
      final guitarHits = await src.browse(query: 'acoustic guitar');
      expect(guitarHits.map((i) => i.title), contains('Acoustic Guitar'));

      // The ambiguous piano page must NOT surface under the default policy.
      final pianoHits = await src.browse(query: 'acoustic grand piano');
      expect(pianoHits, isEmpty);

      // Nor the CC BY drum kit, by default…
      expect(await src.browse(query: 'acoustic drum kit'), isEmpty);
      // …but it does with attribution licences opted in.
      final optIn = FreepatsSource(
        http,
        policy: const LicensePolicy(allowAttributionLicenses: true),
      );
      expect(await optIn.browse(query: 'acoustic drum kit'), isNotEmpty);
    });

    test('a resolved item points at an absolute .7z URL on the same dir',
        () async {
      Future<Uint8List> http(Uri url) async =>
          Uint8List.fromList(utf8.encode(guitar));
      final item = (await FreepatsSource(http).resolve(
        'Guitar/acoustic-guitar.html',
      ))!;
      expect(item.format, '7z');
      expect(item.downloadUrl.toString(), startsWith('https://freepats'));
      expect(item.downloadUrl.toString(), contains('/Guitar/'));
      expect(item.downloadUrl.toString(), endsWith('.7z'));
    });

    test('fetch refuses to download anything the policy blocks', () async {
      Future<Uint8List> http(Uri url) async => Uint8List(0);
      final blocked = LibraryItem(
        sourceId: 'freepats',
        sourceName: 'Freepats',
        id: 'x',
        title: 'x',
        composer: '',
        declaredLicense: kFreepatsAmbiguous,
        downloadUrl: Uri.parse('https://freepats.zenvoid.org/x.7z'),
        format: '7z',
      );
      expect(
        () => FreepatsSource(http).fetch(blocked),
        throwsA(isA<LicenseBlocked>()),
      );
    });

    test('resolve() reports a single unreachable page without throwing',
        () async {
      Future<Uint8List> http(Uri url) async => throw const SocketException('x');
      final res =
          await FreepatsSource(http).resolveDetailed('Ethnic/kalimba.html');
      expect(res.item, isNull);
      expect(res.reason, FreepatsSkipReason.unreachable);
    });
  });

  // A layout change must NOT look like "Freepats has no free packs".
  group('loud failure when the site changes shape', () {
    test('throws when every page parses but has no archive link', () async {
      Future<Uint8List> http(Uri url) async => Uint8List.fromList(
            utf8.encode('<html>CC0 1.0 but no downloads here</html>'),
          );
      final src = FreepatsSource(http);
      await expectLater(
        src.browse(),
        throwsA(
          isA<FreepatsUnavailable>().having(
            (e) => e.message,
            'message',
            contains('layout changed'),
          ),
        ),
      );
      expect(
        src.lastSkips.every(
          (s) => s.reason == FreepatsSkipReason.noArchiveLink,
        ),
        isTrue,
      );
    });

    test('throws when the site is unreachable', () async {
      Future<Uint8List> http(Uri url) async => throw const SocketException('x');
      await expectLater(
        FreepatsSource(http).browse(),
        throwsA(isA<FreepatsUnavailable>()),
      );
    });

    test('throws when pages carry no licence statement at all', () async {
      Future<Uint8List> http(Uri url) async => Uint8List.fromList(
            utf8.encode('<html><a href="x/y-SFZ.7z">dl</a></html>'),
          );
      final src = FreepatsSource(http);
      await expectLater(src.browse(), throwsA(isA<FreepatsUnavailable>()));
      expect(
        src.lastSkips.first.reason,
        FreepatsSkipReason.noLicenseStatement,
      );
    });

    test('does NOT throw when pages are merely licence-blocked', () async {
      // The site is fine; these packs are just not permissively licensed.
      // Empty-but-quiet is the correct outcome here.
      Future<Uint8List> http(Uri url) async =>
          Uint8List.fromList(utf8.encode(drums)); // CC BY 4.0
      final src = FreepatsSource(http);
      expect(await src.browse(), isEmpty);
      expect(
        src.lastSkips.every(
          (s) => s.reason == FreepatsSkipReason.licenseBlocked,
        ),
        isTrue,
      );
      expect(src.lastSkips.every((s) => !s.reason.isStructural), isTrue);
    });

    test('ambiguous licences are a licence decision, not a site failure',
        () async {
      Future<Uint8List> http(Uri url) async =>
          Uint8List.fromList(utf8.encode(piano)); // CC BY 3.0 *and* CC0
      final src = FreepatsSource(http);
      expect(await src.browse(), isEmpty); // no throw
      expect(
        src.lastSkips.first.reason,
        FreepatsSkipReason.ambiguousLicense,
      );
    });
  });

  testWidgets('pack sheet lists gated packs and returns the picked bytes',
      (tester) async {
    Future<Uint8List> http(Uri url) async {
      if (url.toString().endsWith('.html')) {
        return Uint8List.fromList(utf8.encode(guitar));
      }
      return Uint8List.fromList([1, 2, 3, 4]); // the "archive"
    }

    PickedPack? picked;
    await pumpGame(
      tester,
      Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            picked = await showSamplePackSheet(
              ctx,
              sources: [FreepatsSource(http)],
            );
          },
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Narrow to one result so the row is definitely built (a full listing
    // scrolls, and off-screen ListView children don't exist to find).
    await tester.enterText(find.byType(TextField), 'acoustic guitar');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Every listed pack passed the licence gate.
    expect(find.text('Acoustic Guitar'), findsWidgets);

    await tester.tap(find.text('Acoustic Guitar').first);
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.name, 'Acoustic Guitar');
    expect(picked!.bytes, [1, 2, 3, 4]);
    // Provenance rides along so extracted samples keep their licence.
    expect(picked!.license, isNotNull);
    expect(picked!.sourceUrl, contains('freepats'));
  });
}
