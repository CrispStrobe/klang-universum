// VCSL (CC0 instrument samples) source — tree parsing, path→item mapping, the
// percent-encoding trap (`#` in note names), search + fetch. Fixture-driven:
// no network.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/license_policy.dart';
import 'package:comet_beat/features/library/sources/vcsl_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _tree = '''
{"tree":[
 {"type":"blob","path":"Aerophones/Edge-blown Aerophones/Ball Whistle/Main_BallWhistle_Long-001.wav"},
 {"type":"blob","path":"Aerophones/Edge-blown Aerophones/Baroque Alto Recorder/Staccato/AltRecorder_Stac_A#3_rr1_Main.wav"},
 {"type":"blob","path":"Idiophones/Struck Idiophones/Marimba/Marimba_Hit_C4.wav"},
 {"type":"blob","path":"README.md"},
 {"type":"tree","path":"Aerophones"}
]}
''';

void main() {
  group('parseTree / itemForPath', () {
    test('keeps only WAV blobs and maps the path to instrument + family', () {
      final items = VcslSource.parseTree(_tree);
      expect(items.length, 3); // README.md and the tree entry are skipped

      final marimba = items.firstWhere((i) => i.title.contains('Marimba'));
      expect(marimba.collection, 'Idiophones'); // family
      expect(marimba.title, contains('Marimba')); // instrument
      expect(marimba.format, 'wav');
      expect(marimba.declaredLicense, 'CC0');
    });

    test('a 3-segment path still resolves an instrument', () {
      final item = VcslSource.itemForPath(
        'Aerophones/Edge-blown Aerophones/Ball Whistle/Main_BallWhistle_Long-001.wav',
      )!;
      expect(item.title, startsWith('Ball Whistle · '));
      // underscores prettified
      expect(item.title, contains('Main BallWhistle Long-001'));
    });

    test('non-WAV paths are rejected', () {
      expect(VcslSource.itemForPath('README.md'), isNull);
      expect(VcslSource.itemForPath('Assets/thing.sfz'), isNull);
    });

    test('malformed tree JSON yields an empty catalog, never throws', () {
      expect(VcslSource.parseTree('not json'), isEmpty);
      expect(VcslSource.parseTree('[]'), isEmpty);
      expect(VcslSource.parseTree('{"tree":"nope"}'), isEmpty);
    });
  });

  group('raw URL encoding', () {
    test('percent-encodes spaces AND the # in note names', () {
      final url = VcslSource.rawUrlFor(
        'Aerophones/Edge-blown Aerophones/Baroque Alto Recorder/Staccato/AltRecorder_Stac_A#3_rr1_Main.wav',
      );
      // A raw '#' would truncate the URL at the fragment — it must be escaped.
      expect(url.toString(), contains('%23'));
      expect(url.toString(), isNot(contains('#')));
      expect(url.fragment, isEmpty);
      expect(url.toString(), contains('Edge-blown%20Aerophones'));
      expect(url.toString(), startsWith('https://raw.githubusercontent.com/'));
    });
  });

  group('browse / fetch (injected http)', () {
    test('searches by instrument and fetches the file bytes', () async {
      final calls = <Uri>[];
      Future<Uint8List> http(Uri url) async {
        calls.add(url);
        if (url.host == 'api.github.com') {
          return Uint8List.fromList(utf8.encode(_tree));
        }
        return Uint8List.fromList([1, 2, 3]);
      }

      final src = VcslSource(http);
      final hits = await src.browse(query: 'marimba');
      expect(hits.single.title, contains('Marimba'));

      final bytes = await src.fetch(hits.single);
      expect(bytes, [1, 2, 3]);
      expect(calls.last.toString(), contains('Marimba_Hit_C4.wav'));
    });

    test('the catalog is fetched once and reused across browses', () async {
      var treeFetches = 0;
      Future<Uint8List> http(Uri url) async {
        if (url.host == 'api.github.com') treeFetches++;
        return Uint8List.fromList(utf8.encode(_tree));
      }

      final src = VcslSource(http);
      await src.browse();
      await src.browse(query: 'ball');
      expect(treeFetches, 1);
    });

    test('every item passes the DEFAULT (CC0-only) license gate', () async {
      const policy = LicensePolicy();
      for (final item in VcslSource.parseTree(_tree)) {
        expect(
          policy.allows(policy.classify(item.declaredLicense)),
          isTrue,
          reason: '${item.title} declared ${item.declaredLicense}',
        );
      }
    });
  });

  group('loud failure instead of a silent empty listing', () {
    test('a rate-limit / error payload throws rather than listing nothing',
        () async {
      // What GitHub actually returns when it throttles you.
      Future<Uint8List> http(Uri url) async => Uint8List.fromList(
            utf8.encode('{"message":"API rate limit exceeded"}'),
          );
      await expectLater(
        VcslSource(http).browse(),
        throwsA(
          isA<VcslUnavailable>().having(
            (e) => e.message,
            'message',
            contains('rate-limiting'),
          ),
        ),
      );
    });

    test('malformed JSON throws too', () async {
      Future<Uint8List> http(Uri url) async =>
          Uint8List.fromList(utf8.encode('<html>502 Bad Gateway</html>'));
      await expectLater(
        VcslSource(http).browse(),
        throwsA(isA<VcslUnavailable>()),
      );
    });
  });
}
