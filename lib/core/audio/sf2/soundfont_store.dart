// lib/core/audio/sf2/soundfont_store.dart
//
// NATIVE (dart:io) SoundFont provisioning for the CLI — resolves a `--sf2`
// argument that is EITHER a local file path (used as-is) OR a curated catalog id
// (e.g. `fluidr3_gm`), downloading + caching the latter on first use. Mirrors the
// transcription model stores' download→cache pattern and reuses the
// permissively-licensed `SoundFontSource` catalog + license gate from the
// Flutter-free `sf2_remote.dart`.
//
// Kept out of the web-safe core (dart:io); the download seam ([ByteFetcher]) is
// injectable so the resolve/gate/cache flow is unit-testable without a real
// (~140 MB) download.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2_remote.dart'
    show ByteFetcher, SoundFontSource, isPermissiveLicense;

// ─────────────────────────── the curated catalog ────────────────────────────
// Every entry is verified REACHABLE and permissively licensed. `.sf2` is
// uncompressed (plays with no native decoder); `.sf3` is OGG-compressed and
// needs the glint decoder (GLINT_LIB) at render time — the download needs
// nothing.
//
// ⚠ The catalog once named "FluidR3_GM" from archive.org — that item never
// existed as a clean copy, AND the ORIGINAL FluidR3 GM (Frank Wen) is in fact
// "All Rights Reserved … you may not redistribute any part of my work … without
// my written consent" (per its own readme) — NOT redistributable. The
// genuinely-MIT FluidR3 lineage is the RE-releases: FluidR3Mono (Michael
// Cowgill's mono conversion) and MuseScore_General — those are what we use.

/// GeneralUser GS (S. Christian Collins) — compact (~32 MB) full GM bank,
/// uncompressed `.sf2` (no decoder needed). License v2.0 is genuinely permissive
/// but NOT an SPDX id ("use without restriction … private or commercial … feel
/// free to use it in your software projects, and to modify [it]"), so it is
/// allowlisted explicitly ([_permitted]). The default — smallest no-glint bank.
const kGeneralUserGs = SoundFontSource(
  id: 'generaluser_gs',
  name: 'GeneralUser GS (S. Christian Collins)',
  url: 'https://github.com/mrbumpy409/GeneralUser-GS/raw/main/'
      'GeneralUser-GS.sf2',
  license: 'GeneralUser-GS-2.0',
  attribution:
      'GeneralUser GS by S. Christian Collins — GeneralUser GS License '
      'v2.0 (free private/commercial use, redistribution & modification allowed)',
  approxBytes: 32319396,
);

/// FluidR3Mono (Michael Cowgill) — the FluidR3 GM lineage, mono-converted and
/// OGG-compressed to ~14 MB `.sf3` and RE-LICENSED MIT by Cowgill (the original
/// Frank Wen FluidR3 is all-rights-reserved; this mono conversion is the clean
/// MIT one). The smallest bank; needs GLINT_LIB to render.
const kFluidR3Mono = SoundFontSource(
  id: 'fluidr3mono',
  name: 'FluidR3Mono GM (.sf3, needs glint)',
  url: 'https://github.com/musescore/MuseScore/raw/2.1/share/sound/'
      'FluidR3Mono_GM.sf3',
  license: 'MIT',
  attribution: 'FluidR3Mono — mono conversion by Michael Cowgill, MIT '
      '(from Frank Wen\'s FluidR3)',
  approxBytes: 14563174,
);

/// MuseScore_General (.sf3, S. Christian Collins, FluidR3-based) — MIT, ~40 MB
/// OGG-compressed (needs GLINT_LIB to render). A richer FluidR3 descendant.
const kMuseScoreGeneralSf3 = SoundFontSource(
  id: 'musescore_general_sf3',
  name: 'MuseScore General (.sf3, needs glint)',
  url: 'https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/'
      'MuseScore_General.sf3',
  license: 'MIT',
  attribution:
      'MuseScore_General by S. Christian Collins (FluidR3-based) — MIT',
  approxBytes: 39900972,
);

/// MuseScore_General (.sf2, uncompressed) — the same MIT, FluidR3-derived bank as
/// a ~215 MB uncompressed `.sf2` (no decoder needed; large). The clean-MIT,
/// no-glint, full-quality option.
const kMuseScoreGeneral = SoundFontSource(
  id: 'musescore_general',
  name: 'MuseScore General (.sf2, uncompressed)',
  url: 'https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/'
      'MuseScore_General.sf2',
  license: 'MIT',
  attribution:
      'MuseScore_General by S. Christian Collins (FluidR3-based) — MIT',
  approxBytes: 215614036,
);

/// The GeneralUser GS license id, allowlisted alongside the SPDX-permissive set.
const _generalUserLicense = 'GeneralUser-GS-2.0';

/// The soundfonts the CLI can auto-download, smallest/most-convenient first.
const kSoundFontCatalog = <SoundFontSource>[
  kGeneralUserGs, // 32 MB .sf2, no glint — the default
  kFluidR3Mono, // 14 MB .sf3 (needs glint) — the clean-MIT FluidR3 lineage
  kMuseScoreGeneralSf3, // 40 MB .sf3 (needs glint), MIT
  kMuseScoreGeneral, // 215 MB .sf2, MIT — clean + no glint, but large
];

/// Whether [license] is permissive enough to auto-download: the SPDX-permissive
/// allowlist, plus the explicitly-verified GeneralUser GS custom license.
bool _permitted(String license) =>
    isPermissiveLicense(license) || license == _generalUserLicense;

/// The file extension a source's URL implies (`.sf3` or `.sf2`).
String _extOf(String url) =>
    url.toLowerCase().endsWith('.sf3') ? '.sf3' : '.sf2';

/// Resolves a `--sf2` argument to a local `.sf2` file path, downloading a
/// catalog soundfont on first use and caching it under
/// `~/.cache/comet_beat/soundfonts/` (override with `COMET_SOUNDFONT_DIR`).
class SoundFontStore {
  SoundFontStore({
    this.cacheDirOverride,
    this.mirrorBaseOverride,
    List<SoundFontSource>? catalog,
    ByteFetcher? fetch,
    void Function(String)? log,
  })  : catalog = catalog ?? kSoundFontCatalog,
        _fetch = fetch ?? _httpGet,
        _log = log ?? stderr.writeln;

  final String? cacheDirOverride;

  /// If set (or via `COMET_SOUNDFONT_MIRROR`), download from
  /// `<mirror>/<id><ext>` instead of the source's upstream URL — the hook for a
  /// self-hosted, license-vetted mirror (e.g. a GitHub release we control).
  final String? mirrorBaseOverride;

  final List<SoundFontSource> catalog;
  final ByteFetcher _fetch;
  final void Function(String) _log;

  /// A downloaded soundfont must be at least this big (guards partial fetches).
  static const _minBytes = 100000;

  String cacheDir() {
    if (cacheDirOverride != null && cacheDirOverride!.isNotEmpty) {
      return cacheDirOverride!;
    }
    final env = Platform.environment['COMET_SOUNDFONT_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.cache/comet_beat/soundfonts';
  }

  /// The self-hosted mirror base, or null. A trailing slash is optional.
  String? mirrorBase() {
    final m =
        mirrorBaseOverride ?? Platform.environment['COMET_SOUNDFONT_MIRROR'];
    return (m != null && m.isNotEmpty) ? m : null;
  }

  /// The upstream (or mirrored) download URL for [s].
  String urlFor(SoundFontSource s) {
    final mirror = mirrorBase();
    if (mirror == null) return s.url;
    final base = mirror.endsWith('/') ? mirror : '$mirror/';
    return '$base${s.id}${_extOf(s.url)}';
  }

  File fileFor(SoundFontSource s) =>
      File('${cacheDir()}/${s.id}${_extOf(s.url)}');

  bool isPresent(SoundFontSource s) {
    final f = fileFor(s);
    return f.existsSync() && f.lengthSync() > _minBytes;
  }

  /// The catalog source matching [nameOrId] (by id or display name), or null.
  SoundFontSource? sourceFor(String nameOrId) {
    for (final s in catalog) {
      if (s.id == nameOrId || s.name == nameOrId) return s;
    }
    return null;
  }

  /// Resolves [nameOrPath] to a local `.sf2` file path.
  ///
  /// An existing file path is returned unchanged. Otherwise it is looked up in
  /// the catalog and downloaded (license-gated) + cached on first use.
  ///
  /// Throws [ArgumentError] for an unknown name, [StateError] if the source
  /// isn't permissively licensed or the download fails/short.
  Future<String> resolve(String nameOrPath) async {
    if (File(nameOrPath).existsSync()) return nameOrPath;

    final source = sourceFor(nameOrPath);
    if (source == null) {
      throw ArgumentError(
        'unknown SoundFont "$nameOrPath" — pass a .sf2 file path, or a catalog '
        'id: ${catalog.map((s) => s.id).join(", ")}',
      );
    }
    if (!_permitted(source.license)) {
      throw StateError(
        'refusing to download "${source.name}": '
        '${source.license} is not a permissive license',
      );
    }

    final file = fileFor(source);
    if (isPresent(source)) return file.path;

    final url = urlFor(source);
    final mb = ((source.approxBytes ?? 0) / 1000000).round();
    _log('Downloading ${source.name} '
        '(~$mb MB, ${source.license}) → ${file.path} …');
    final Uint8List bytes;
    try {
      bytes = await _fetch(Uri.parse(url));
    } catch (e) {
      throw StateError('SoundFont download failed ($url): $e');
    }
    if (bytes.length < _minBytes) {
      throw StateError(
        'SoundFont download too small (${bytes.length} bytes) from $url',
      );
    }
    Directory(cacheDir()).createSync(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// A human-readable listing of the auto-downloadable catalog.
  String describeCatalog() {
    final b =
        StringBuffer('Auto-downloadable SoundFonts (pass the id to --sf2):\n');
    for (final s in catalog) {
      final mb = s.approxBytes != null
          ? ' (~${(s.approxBytes! / 1000000).round()} MB)'
          : '';
      final glint = _extOf(s.url) == '.sf3' ? ' [.sf3 — needs GLINT_LIB]' : '';
      b.writeln('  ${s.id.padRight(20)} ${s.name}$mb — ${s.license}$glint');
      b.writeln('  ${' '.padRight(20)} ${s.attribution}');
    }
    final mirror = mirrorBase();
    if (mirror != null) b.writeln('mirror: $mirror');
    return b.toString();
  }

  /// A redirect-following HTTP GET (GitHub / osuosl mirrors may redirect).
  static Future<Uint8List> _httpGet(Uri url) async {
    final client = HttpClient()..userAgent = 'comet_beat-soundfont';
    try {
      var uri = url;
      for (var hop = 0; hop < 6; hop++) {
        final req = await client.getUrl(uri);
        req.followRedirects = false;
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final b = BytesBuilder(copy: false);
          await for (final chunk in resp) {
            b.add(chunk);
          }
          return b.takeBytes();
        }
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (resp.isRedirect && loc != null) {
          uri = Uri.parse(loc).hasScheme ? Uri.parse(loc) : uri.resolve(loc);
          continue;
        }
        throw HttpException('HTTP ${resp.statusCode}', uri: uri);
      }
      throw const HttpException('too many redirects');
    } finally {
      client.close(force: true);
    }
  }
}
