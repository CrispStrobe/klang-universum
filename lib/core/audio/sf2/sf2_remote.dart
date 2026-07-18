// On-demand SoundFont download — fetch a permissively-licensed `.sf2` by URL,
// cache it, and parse it into GM instruments. This avoids bundling a large
// soundfont in the app (FluidR3_GM.sf2 is ~140 MB); the user downloads it once
// on demand and it's cached on disk thereafter.
//
// Flutter-free: the network fetch and disk cache are injected seams
// ([ByteFetcher] / [SoundFontCache]), so the fetch→gate→parse flow is
// unit-testable without a device, a plugin, or a real 140 MB download. The app
// supplies an `http`-backed fetcher and a `path_provider`-backed cache.
//
// A permissive-LICENSE gate runs BEFORE any download: only known-permissive
// soundfonts (MIT / CC0 / Apache / BSD / CC-BY[-SA]) are ever fetched, matching
// the sound-library licensing policy (see docs/PLAN.md).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart';

/// Fetches the bytes at [url]. The app backs this with `http`; tests inject a
/// fake. Should throw on a network/HTTP error.
typedef ByteFetcher = Future<Uint8List> Function(Uri url);

/// A disk cache for downloaded soundfonts (keyed by [SoundFontSource.id]). The
/// app backs this with `path_provider`; tests use an in-memory map. Optional —
/// omit to always fetch.
abstract class SoundFontCache {
  Future<Uint8List?> read(String id);
  Future<void> write(String id, Uint8List bytes);
}

/// A curated, permissively-licensed soundfont the app can offer for download.
/// Only UNCOMPRESSED `.sf2` (the parser doesn't decode `.sf3`/OGG yet).
class SoundFontSource {
  const SoundFontSource({
    required this.id,
    required this.name,
    required this.url,
    required this.license,
    required this.attribution,
    this.approxBytes,
  });

  final String id;
  final String name;
  final String url;

  /// SPDX id of the license — MUST be permissive (gated by [isPermissiveLicense]).
  final String license;

  /// The credit line to show (kept even for CC0/MIT as good practice).
  final String attribution;

  /// Rough download size, for a "this is ~N MB" confirmation prompt.
  final int? approxBytes;
}

/// The permissive SPDX allowlist for bundling/redistribution: public-domain
/// (CC0), permissive-notice (MIT/Apache/BSD), and attribution CC licenses. NC /
/// ND / all-rights-reserved / unknown are NOT permissive.
bool isPermissiveLicense(String spdx) => const {
      'CC0-1.0',
      'MIT',
      'Apache-2.0',
      'BSD-3-Clause',
      'BSD-2-Clause',
      'CC-BY-4.0',
      'CC-BY-3.0',
      'CC-BY-SA-4.0',
      'CC-BY-SA-3.0',
    }.contains(spdx.trim());

/// The MIT FluidR3_GM soundfont — the canonical full General-MIDI set (uncompressed
/// `.sf2`, ~140 MB). The [url] is a configurable mirror; the app should confirm
/// the download size with the user first. (MuseScore's FluidR3Mono is `.sf3`
/// (OGG) which the parser doesn't decode yet — hence the full `.sf2` here.)
const kFluidR3Gm = SoundFontSource(
  id: 'fluidr3_gm',
  name: 'FluidR3 GM (General MIDI)',
  // A configurable mirror — the app should confirm the ~140 MB download first
  // and may point this at a verified host.
  url: 'https://archive.org/download/fluidr3-gm/FluidR3_GM.sf2',
  license: 'MIT',
  attribution: 'FluidR3 GM by Frank Wen — MIT license',
  approxBytes: 148000000,
);

/// Download [source] (gate → cache-hit-or-fetch → cache) and parse it into an
/// [Sf2SoundFont]. Throws [StateError] if the source isn't permissively licensed
/// (before any network access), or [FormatException] if the bytes aren't a valid
/// uncompressed `.sf2`.
Future<Sf2SoundFont> downloadSoundFont(
  SoundFontSource source, {
  required ByteFetcher fetch,
  SoundFontCache? cache,
}) async {
  if (!isPermissiveLicense(source.license)) {
    throw StateError(
      'refusing to download "${source.name}": '
      '${source.license} is not a permissive license',
    );
  }
  final cached = await cache?.read(source.id);
  if (cached != null) return Sf2SoundFont.parse(cached);

  final bytes = await fetch(Uri.parse(source.url));
  await cache?.write(source.id, bytes);
  return Sf2SoundFont.parse(bytes);
}
