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
    show ByteFetcher, SoundFontSource, isPermissiveLicense, kFluidR3Gm;

/// The soundfonts the CLI can auto-download — permissively licensed, uncompressed
/// `.sf2` (so no native OGG decoder is needed). Add more `SoundFontSource`s here.
const kSoundFontCatalog = <SoundFontSource>[kFluidR3Gm];

/// Resolves a `--sf2` argument to a local `.sf2` file path, downloading a
/// catalog soundfont on first use and caching it under
/// `~/.cache/comet_beat/soundfonts/` (override with `COMET_SOUNDFONT_DIR`).
class SoundFontStore {
  SoundFontStore({
    this.cacheDirOverride,
    List<SoundFontSource>? catalog,
    ByteFetcher? fetch,
    void Function(String)? log,
  })  : catalog = catalog ?? kSoundFontCatalog,
        _fetch = fetch ?? _httpGet,
        _log = log ?? stderr.writeln;

  final String? cacheDirOverride;
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

  File fileFor(SoundFontSource s) => File('${cacheDir()}/${s.id}.sf2');

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
    if (!isPermissiveLicense(source.license)) {
      throw StateError(
        'refusing to download "${source.name}": '
        '${source.license} is not a permissive license',
      );
    }

    final file = fileFor(source);
    if (isPresent(source)) return file.path;

    final mb = ((source.approxBytes ?? 0) / 1000000).round();
    _log('Downloading ${source.name} '
        '(~$mb MB, ${source.license}) → ${file.path} …');
    final Uint8List bytes;
    try {
      bytes = await _fetch(Uri.parse(source.url));
    } catch (e) {
      throw StateError('SoundFont download failed (${source.url}): $e');
    }
    if (bytes.length < _minBytes) {
      throw StateError(
        'SoundFont download too small (${bytes.length} bytes) from ${source.url}',
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
      b.writeln('  ${s.id.padRight(14)} ${s.name}$mb — ${s.license}');
      b.writeln('  ${' '.padRight(14)} ${s.attribution}');
    }
    return b.toString();
  }

  /// A redirect-following HTTP GET (archive.org and mirrors redirect).
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
