// The connector's content-source abstraction. A `ContentSource` browses an
// external open-music library and fetches an item's bytes; the app never talks
// to a specific site directly. Adding a source = one adapter implementing this
// interface + a `SourceRegistry` entry. All I/O goes through an injectable
// [HttpGet] so the sources are unit-testable without a live network.

import 'dart:typed_data';

/// Minimal HTTP GET seam — returns the raw bytes at [url] or throws. Injected
/// so tests feed fixtures and production uses `package:http` (see
/// `source_registry.dart`).
typedef HttpGet = Future<Uint8List> Function(Uri url);

/// One browsable/importable work from a [ContentSource]. Carries everything the
/// license gate + provenance need, so nothing has to be re-fetched to attribute
/// it. Pure data.
class LibraryItem {
  /// Id of the owning [ContentSource].
  final String sourceId;

  /// Human name of the owning source (e.g. "OpenScore Lieder").
  final String sourceName;

  /// Stable id within the source (e.g. the OpenScore `lc…` id).
  final String id;

  final String title;
  final String composer;

  /// A grouping within the source (opus/set), or empty.
  final String collection;

  /// The declared license as the source states it (free text — classified by
  /// `LicensePolicy`, never trusted blindly). E.g. "CC0", "CC BY-SA 4.0".
  final String declaredLicense;

  /// Canonical URL for the license deed, or null.
  final String? licenseUrl;

  /// Human page for the work (for a "view source" link), or null.
  final String? sourceUrl;

  /// Direct download URL for [format]'s bytes.
  final Uri downloadUrl;

  /// Download format: `mxl`, `musicxml`, `midi`, or `abc`.
  final String format;

  const LibraryItem({
    required this.sourceId,
    required this.sourceName,
    required this.id,
    required this.title,
    required this.composer,
    this.collection = '',
    required this.declaredLicense,
    this.licenseUrl,
    this.sourceUrl,
    required this.downloadUrl,
    required this.format,
  });
}

/// A browsable external open-music library. Implementations are thin adapters
/// over one site's API/bulk mirror; they must only ever surface items the
/// source publishes under a permissive license (the `LicensePolicy` gate is the
/// backstop, not the first line of defence).
abstract class ContentSource {
  /// Stable source id (matches `LibraryItem.sourceId`).
  String get id;

  /// Display name.
  String get name;

  /// The site's home page.
  String get homepage;

  /// One-line license summary shown in the UI (e.g. "CC0 — public domain").
  String get licenseSummary;

  /// Browses the source, optionally filtered by a free-text [query] (matched
  /// against title/composer). Returns up to [limit] items.
  Future<List<LibraryItem>> browse({String query = '', int limit = 60});

  /// Downloads [item]'s bytes in its [LibraryItem.format].
  Future<Uint8List> fetch(LibraryItem item);
}
