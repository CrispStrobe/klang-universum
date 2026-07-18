// The license gate — the compliance spine of the library connector. Every item
// passes through `LicensePolicy` before it can be imported: a declared license
// string is classified, non-permissive licenses are blocked, and a human
// attribution line is produced for the ones we keep.
//
// Permissive allowlist for *bundling/redistribution* in a store-distributed
// app: Public Domain, CC0, CC BY, CC BY-SA. Everything else — NC, ND,
// all-rights-reserved, unknown/absent — is blocked. (Rationale + sources in
// docs/LIBRARIES_AND_TAB_SCOPING.md §1.5.)

import 'package:comet_beat/features/library/content_source.dart';

/// The classified license family of an item.
enum LicenseKind {
  publicDomain,
  cc0,
  ccBy,
  ccBySa,
  ccByNc,
  ccByNd,
  allRightsReserved,
  unknown;

  /// May we bundle/redistribute this in the app? Only PD/CC0/BY/BY-SA.
  bool get isPermissive =>
      this == publicDomain || this == cc0 || this == ccBy || this == ccBySa;

  /// A short label for the UI.
  String get label => switch (this) {
        publicDomain => 'Public Domain',
        cc0 => 'CC0',
        ccBy => 'CC BY',
        ccBySa => 'CC BY-SA',
        ccByNc => 'CC BY-NC',
        ccByNd => 'CC BY-ND',
        allRightsReserved => 'All rights reserved',
        unknown => 'Unknown license',
      };
}

/// Thrown by [LicensePolicy.gate] when an item's license is not on the
/// permissive allowlist. Carries the classified [kind] so the UI can explain.
class LicenseBlocked implements Exception {
  final LibraryItem item;
  final LicenseKind kind;
  const LicenseBlocked(this.item, this.kind);

  @override
  String toString() =>
      'LicenseBlocked(${item.title}: ${kind.label} is not permissive)';
}

/// Classifies declared-license text and gates imports. Pure + stateless, so it
/// is the highest-value unit test in the connector.
class LicensePolicy {
  const LicensePolicy();

  /// Classifies a free-text declared license into a [LicenseKind]. Conservative:
  /// anything it can't confidently read as permissive falls through to
  /// [LicenseKind.unknown] (which the gate blocks). NC/ND are detected *before*
  /// the plain BY/BY-SA checks so "CC BY-NC" never reads as "CC BY".
  LicenseKind classify(String declared) {
    final s = declared.toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ').trim();
    if (s.isEmpty) return LicenseKind.unknown;

    final isCc = s.contains('cc') || s.contains('creative commons');
    final nc = s.contains('nc') ||
        s.contains('noncommercial') ||
        s.contains('non-commercial');
    final nd = s.contains('nd') || s.contains('noderiv');

    // Public domain / CC0 first (no conditions).
    if (s.contains('cc0') ||
        s.contains('publicdomain') ||
        s.contains('public domain') ||
        s == 'pd' ||
        s.contains('zero')) {
      return s.contains('cc0') || s.contains('zero')
          ? LicenseKind.cc0
          : LicenseKind.publicDomain;
    }

    if (isCc) {
      // Restrictive variants take priority over the permissive read.
      if (nc) return LicenseKind.ccByNc;
      if (nd) return LicenseKind.ccByNd;
      if (s.contains('by sa') || s.contains('by-sa') || s.contains('bysa')) {
        return LicenseKind.ccBySa;
      }
      if (s.contains('by')) return LicenseKind.ccBy;
      return LicenseKind.unknown; // "CC" with no recognisable clause
    }

    if (s.contains('all rights reserved') || s.contains('copyright')) {
      return LicenseKind.allRightsReserved;
    }
    return LicenseKind.unknown;
  }

  /// True if [item] may be imported/bundled.
  bool isAllowed(LibraryItem item) =>
      classify(item.declaredLicense).isPermissive;

  /// Throws [LicenseBlocked] if [item] is not permissively licensed; otherwise
  /// returns the classified kind. Call this before any fetch/store.
  LicenseKind gate(LibraryItem item) {
    final kind = classify(item.declaredLicense);
    if (!kind.isPermissive) throw LicenseBlocked(item, kind);
    return kind;
  }

  /// The human attribution line stored with an imported work and shown on the
  /// "Sources & credits" screen. PD/CC0 need no credit but we still record the
  /// source; BY/BY-SA name the author + license.
  String attributionFor(LibraryItem item) {
    final kind = classify(item.declaredLicense);
    final who = item.composer.isEmpty ? '' : ' by ${item.composer}';
    return '“${item.title}”$who — ${kind.label}. Source: ${item.sourceName}.';
  }
}
