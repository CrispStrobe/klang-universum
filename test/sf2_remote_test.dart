// On-demand SoundFont download: the fetch→gate→cache→parse flow with an
// injected fake fetcher + in-memory cache (no network, no device). Reuses the
// SF2 fixture writer to synthesize a valid soundfont to "download".

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';
import 'package:comet_beat/core/audio/sf2/sf2_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sf2_fixture.dart';

class _MemCache implements SoundFontCache {
  final Map<String, Uint8List> store = {};
  @override
  Future<Uint8List?> read(String id) async => store[id];
  @override
  Future<void> write(String id, Uint8List bytes) async => store[id] = bytes;
}

void main() {
  final sf2Bytes = oneSampleSf2(
    pcm: sineI16(880, 20),
    sampleRate: 44100,
    rootKey: 60,
    loopStart: 0,
    loopEnd: 0,
  );

  const permissive = SoundFontSource(
    id: 'test_sf',
    name: 'Test SF',
    url: 'https://example.com/test.sf2',
    license: 'MIT',
    attribution: 'test',
  );

  group('on-demand SoundFont download', () {
    test('isPermissiveLicense: MIT/CC0 allowed, NC/unknown blocked', () {
      expect(isPermissiveLicense('MIT'), isTrue);
      expect(isPermissiveLicense('CC0-1.0'), isTrue);
      expect(isPermissiveLicense('CC-BY-SA-4.0'), isTrue);
      expect(isPermissiveLicense('CC-BY-NC-4.0'), isFalse);
      expect(isPermissiveLicense('CC-BY-ND-4.0'), isFalse);
      expect(isPermissiveLicense('All rights reserved'), isFalse);
      expect(isPermissiveLicense('GPL-2.0'), isFalse);
      // The bundled FluidR3 source is MIT (permissive).
      expect(isPermissiveLicense(kFluidR3Gm.license), isTrue);
    });

    test('fetches, parses, and caches a permissive soundfont', () async {
      var fetches = 0;
      final cache = _MemCache();
      Future<Uint8List> fetch(Uri url) async {
        fetches++;
        return sf2Bytes;
      }

      final sf =
          await downloadSoundFont(permissive, fetch: fetch, cache: cache);
      expect(sf, isA<Sf2SoundFont>());
      expect(sf.presets, isNotEmpty);
      expect(fetches, 1);
      expect(cache.store.containsKey('test_sf'), isTrue);

      // Second call hits the cache — no second fetch.
      final again =
          await downloadSoundFont(permissive, fetch: fetch, cache: cache);
      expect(again.presets, isNotEmpty);
      expect(fetches, 1);
    });

    test('refuses a non-permissive source BEFORE fetching', () async {
      const nc = SoundFontSource(
        id: 'nc',
        name: 'NC font',
        url: 'https://example.com/nc.sf2',
        license: 'CC-BY-NC-4.0',
        attribution: 'x',
      );
      var fetched = false;
      Future<Uint8List> fetch(Uri url) async {
        fetched = true;
        return sf2Bytes;
      }

      await expectLater(
        downloadSoundFont(nc, fetch: fetch),
        throwsStateError,
      );
      expect(fetched, isFalse); // gate ran before any network access
    });
  });
}
