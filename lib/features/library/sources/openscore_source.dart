// OpenScore Lieder — the connect-first source. ~1,300 19th-century art songs,
// volunteer-transcribed, released under **CC0** (public domain dedication). We
// pull from the GitHub mirror (OpenScore/Lieder), NOT musescore.com, so we never
// touch that site's ToS/paywall. See docs/LIBRARIES_AND_TAB_SCOPING.md §1.1.
//
// Layout on the mirror:
//   scores/<Composer>/<Set or _>/<Song_Title>/lc<id>.mxl   (compressed MusicXML)
// Browse = read the git tree once, filter the .mxl files, parse composer/title
// from the path. Download = the raw.githubusercontent.com URL for that path.

import 'dart:convert';
import 'dart:typed_data';

import 'package:comet_beat/features/library/content_source.dart';

/// CC0 art-song corpus, browsed from the OpenScore/Lieder GitHub mirror.
class OpenScoreSource implements ContentSource {
  final HttpGet _http;

  /// Cached file paths (`scores/…/lc….mxl`) from the git tree, fetched lazily.
  List<String>? _paths;

  OpenScoreSource(this._http);

  @override
  String get id => 'openscore_lieder';

  @override
  String get name => 'OpenScore Lieder';

  @override
  String get homepage => 'https://github.com/OpenScore/Lieder';

  @override
  String get licenseSummary => 'CC0 — public domain';

  static final Uri _treeUrl = Uri.parse(
    'https://api.github.com/repos/OpenScore/Lieder/git/trees/main?recursive=1',
  );

  /// The declared license every OpenScore item carries.
  static const declaredLicense = 'CC0';
  static const _licenseUrl =
      'https://creativecommons.org/publicdomain/zero/1.0/';

  Future<List<String>> _loadPaths() async {
    final cached = _paths;
    if (cached != null) return cached;
    final bytes = await _http(_treeUrl);
    final paths = parseTreePaths(utf8.decode(bytes));
    _paths = paths;
    return paths;
  }

  /// Extracts the `.mxl` score paths from a GitHub git-tree JSON body. Static +
  /// pure so it is unit-testable against a captured fixture.
  static List<String> parseTreePaths(String treeJson) {
    final root = json.decode(treeJson) as Map<String, dynamic>;
    final tree = root['tree'] as List? ?? [];
    final out = <String>[];
    for (final e in tree) {
      final path = (e as Map<String, dynamic>)['path'] as String?;
      if (path != null && path.startsWith('scores/') && path.endsWith('.mxl')) {
        out.add(path);
      }
    }
    out.sort();
    return out;
  }

  /// Builds a [LibraryItem] from a `scores/<composer>/<set>/<title>/lc<id>.mxl`
  /// path. Static + pure. Returns null for a path that doesn't match.
  LibraryItem? itemForPath(String path) {
    final segs = path.split('/');
    if (segs.length < 5 || segs.first != 'scores') return null;
    final composer = _humanize(segs[1]);
    final collection = segs[2] == '_' ? '' : _humanize(segs[2]);
    final title = _humanize(segs[3]);
    final file = segs.last;
    final scoreId = file.substring(0, file.length - '.mxl'.length);
    return LibraryItem(
      sourceId: id,
      sourceName: name,
      id: scoreId,
      title: title,
      composer: composer,
      collection: collection,
      declaredLicense: declaredLicense,
      licenseUrl: _licenseUrl,
      sourceUrl:
          'https://github.com/OpenScore/Lieder/tree/main/${segs.sublist(0, 4).join('/')}',
      downloadUrl: Uri(
        scheme: 'https',
        host: 'raw.githubusercontent.com',
        pathSegments: ['OpenScore', 'Lieder', 'main', ...segs],
      ),
      format: 'mxl',
    );
  }

  /// "Arne,_Thomas" → "Thomas Arne"; "Rule,_Britannia!" → "Rule, Britannia!".
  static String _humanize(String seg) {
    final s = seg.replaceAll('_', ' ').trim();
    // "Surname, Given" → "Given Surname" for a composer folder.
    final comma = s.indexOf(', ');
    if (comma > 0 && !s.contains('!') && !s.contains('?')) {
      final surname = s.substring(0, comma);
      final given = s.substring(comma + 2);
      // Only flip when it looks like a name (no long phrase after the comma).
      if (!given.contains(' ') || given.split(' ').length <= 3) {
        return '$given $surname';
      }
    }
    return s;
  }

  @override
  Future<List<LibraryItem>> browse({String query = '', int limit = 60}) async {
    final paths = await _loadPaths();
    final q = query.toLowerCase().trim();
    final out = <LibraryItem>[];
    for (final p in paths) {
      final item = itemForPath(p);
      if (item == null) continue;
      if (q.isNotEmpty &&
          !item.title.toLowerCase().contains(q) &&
          !item.composer.toLowerCase().contains(q)) {
        continue;
      }
      out.add(item);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<Uint8List> fetch(LibraryItem item) => _http(item.downloadUrl);
}
