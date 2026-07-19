// In-app "Download General MIDI" — a curated catalog of freely-licensed,
// full-GM (128-preset) SoundFonts the app can fetch on demand, plus a disk
// cache so the (large) download happens once. This is the app-layer wiring over
// the Flutter-free core `sf2_remote.dart` (its licence gate + `SoundFontSource`
// + `downloadSoundFont` seams) — it adds an `http` fetcher and a `dart:io`
// cache dir (mirroring `basic_pitch_model_store`), which core deliberately
// leaves to the app.
//
// Only PERMISSIVELY-licensed soundfonts are listed (the core gate re-checks
// before any byte is fetched). `.sf3` (Ogg-Vorbis) fonts decode via the glint
// Vorbis path that `loadSoundFont` auto-selects, so the small compressed
// FluidR3Mono is a first-class option alongside the full uncompressed `.sf2`.
//
// Native/desktop only: the cache uses `dart:io`. Web has no place to keep a
// 140 MB font and its own glint-wasm path, so the download button is hidden
// there (the file-pick still works).

import 'dart:io';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2_remote.dart';
import 'package:comet_beat/features/library/source_registry.dart'
    show defaultHttpGet;

/// A compressed (`.sf3`, Ogg-Vorbis) mono re-encoding of FluidR3 GM — the full
/// General-MIDI set at ~1/10th the size of the uncompressed `.sf2`, so it's the
/// friendly default. MIT (it's FluidR3, Frank Wen), decoded via the glint
/// Vorbis path. The [url] is a configurable mirror (as with [kFluidR3Gm]); the
/// maintainer can repoint it at any verified host.
const kFluidR3MonoGm = SoundFontSource(
  id: 'fluidr3mono_gm',
  name: 'FluidR3 Mono GM (General MIDI, compact)',
  url: 'https://github.com/musescore/MuseScore/raw/v2.1/share/sound/'
      'FluidR3Mono_GM.sf3',
  license: 'MIT',
  attribution: 'FluidR3 GM by Frank Wen — MIT license (mono .sf3 re-encode)',
  approxBytes: 13000000,
);

/// The curated download catalog, smallest first: the ~13 MB compact `.sf3` as
/// the recommended default, then the full ~140 MB uncompressed `.sf2`. Both are
/// complete 128-instrument General-MIDI sets under the MIT licence.
const List<SoundFontSource> kGmSoundFonts = [
  kFluidR3MonoGm,
  kFluidR3Gm,
];

/// A human "~13 MB" / "~141 MB" size hint for [source], or '' if unknown.
String soundFontSizeHint(SoundFontSource source) {
  final b = source.approxBytes;
  if (b == null || b <= 0) return '';
  final mb = b / (1024 * 1024);
  return mb >= 10 ? '~${mb.round()} MB' : '~${mb.toStringAsFixed(1)} MB';
}

/// A `dart:io` disk cache for downloaded soundfonts, mirroring
/// `basic_pitch_model_store`'s dir policy: `$COMET_SOUNDFONT_DIR`, else
/// `$HOME/.cache/comet_beat/soundfonts`. Keyed by [SoundFontSource.id] so a
/// re-download is instant.
class IoSoundFontCache implements SoundFontCache {
  IoSoundFontCache({this.cacheDirOverride});

  final String? cacheDirOverride;

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

  File _file(String id) => File('${cacheDir()}/$id.sf');

  /// The cached file for [id] (whether or not it exists yet) — the sheet stores
  /// this as a downloaded voice's `SoundFontRef.path` so it can be rebuilt.
  String pathFor(String id) => _file(id).path;

  @override
  Future<Uint8List?> read(String id) async {
    final f = _file(id);
    if (!f.existsSync() || f.lengthSync() <= 0) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    Directory(cacheDir()).createSync(recursive: true);
    await _file(id).writeAsBytes(bytes);
  }
}

/// Fetch [source]'s bytes (licence-gated → cache-hit-or-download → cache),
/// returning the raw file so the caller can hand them to `loadSoundFont`
/// (which picks the `.sf2`/`.sf3` decoder and gives friendly errors). Throws
/// [StateError] if the source isn't permissively licensed (before any network
/// access); rethrows the fetcher's error offline.
///
/// [fetch] defaults to the app's real HTTP GET and [cache] to [IoSoundFontCache]
/// — tests inject fakes. Mirrors core `downloadSoundFont`, but returns bytes
/// (not a parsed font) so the UI reuses its own load/browse path.
typedef SoundFontBytesDownloader = Future<Uint8List> Function(
  SoundFontSource source,
);

Future<Uint8List> downloadGmSoundFontBytes(
  SoundFontSource source, {
  ByteFetcher? fetch,
  SoundFontCache? cache,
}) async {
  if (!isPermissiveLicense(source.license)) {
    throw StateError(
      'refusing to download "${source.name}": '
      '${source.license} is not a permissive license',
    );
  }
  final store = cache ?? IoSoundFontCache();
  final cached = await store.read(source.id);
  if (cached != null) return cached;

  final fetcher = fetch ?? defaultHttpGet;
  final bytes = await fetcher(Uri.parse(source.url));
  await store.write(source.id, bytes);
  return bytes;
}
