// Shared types for the downloads manager (see downloads_manager.dart).

/// One category of on-disk downloads (AI models, SoundFonts, instrument
/// samples…) — where it lives, how big it is, and how many files.
class DownloadCategory {
  const DownloadCategory({
    required this.id,
    required this.label,
    required this.bytes,
    required this.items,
    required this.path,
  });

  final String id; // the cache subdir name ('models', 'soundfonts', …)
  final String label; // friendly display name
  final int bytes;
  final int items;
  final String path; // absolute dir, for removal

  /// "12.3 MB" / "1.4 GB" / "812 KB".
  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var v = bytes / 1024;
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[u]}';
  }
}
