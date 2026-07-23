// Native (dart:io) downloads manager. Scans the shared cache root
// `$HOME/.cache/comet_beat/` (override `COMET_CACHE_DIR`) — the same root the
// model stores (`…/models`) and the SoundFont cache (`…/soundfonts`) use.
import 'dart:io';

import 'package:comet_beat/features/settings/downloads_manager_types.dart';

bool get downloadsSupported => true;

String _cacheRoot() {
  final env = Platform.environment['COMET_CACHE_DIR'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return '$home/.cache/comet_beat';
}

const _labels = {
  'models': 'AI models (transcription / scan)',
  'soundfonts': 'SoundFonts',
  'instruments': 'Instrument samples',
};

/// Lists each cache subdir with its total size + file count, largest first.
Future<List<DownloadCategory>> scanDownloads({String? rootOverride}) async {
  final root = Directory(rootOverride ?? _cacheRoot());
  if (!root.existsSync()) return const [];
  final out = <DownloadCategory>[];
  for (final entry in root.listSync().whereType<Directory>()) {
    final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    var bytes = 0, items = 0;
    for (final f in entry.listSync(recursive: true).whereType<File>()) {
      try {
        bytes += f.lengthSync();
        items++;
      } catch (_) {}
    }
    if (items == 0) continue;
    out.add(
      DownloadCategory(
        id: id,
        label: _labels[id] ?? id,
        bytes: bytes,
        items: items,
        path: entry.path,
      ),
    );
  }
  out.sort((a, b) => b.bytes.compareTo(a.bytes));
  return out;
}

/// Deletes a category's directory (freeing the space); it re-downloads on next use.
Future<void> clearDownloads(String path) async {
  final d = Directory(path);
  if (d.existsSync()) d.deleteSync(recursive: true);
}
