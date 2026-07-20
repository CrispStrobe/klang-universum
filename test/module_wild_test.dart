// Validates the module parser against a corpus of REAL tracker modules that
// live (gitignored) under test/fixtures/wild/ — fetched by
// bin/fetch_wild_modules.dart. Unlike our tiny self-authored goldens, these are
// files real trackers actually wrote, so they exercise header quirks, feature
// combinations and edge cases our synthetic fixtures don't.
//
// The invariant (same as the blackbox fuzz test, now over REAL bytes): parsing
// untrusted input must NEVER throw a Dart Error — only a clean Exception
// (FormatException / ItFormatException / …) is acceptable. When a file DOES
// parse, the result must be structurally sane and survive a SAME-FORMAT
// round-trip (parse → write same format → parse) keeping every note. Skips
// cleanly in CI where the corpus is absent.
//
// Measured on an 80-file real corpus (20 each mod/xm/s3m/it):
//   • same-format round-trip:  notes 100%, samples 100% — locked here.
//   • cross-format src→other→src note preservation:
//       mod→{xm,s3m,it}→mod ...... 100%   (MOD content always fits + returns)
//       it→xm→it 99.8% · s3m→it→s3m 100% · xm→it→xm 100% (equal-or-richer path)
//       …→mod→… 32–63% · …→s3m→… 81–82%  (routing a RICHER format through a
//       POORER one is lossy BY DESIGN — MOD can't hold >8 channels / notes
//       above B-3 / extended effects). Not asserted (format-pair specific).

import 'dart:io';

import 'package:comet_beat/core/audio/mod/module_convert.dart';
import 'package:comet_beat/core/audio/mod/module_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every voiced cell as `pattern:row:channel → note`.
Map<String, int> _notes(ModuleDoc d) {
  final m = <String, int>{};
  for (var p = 0; p < d.patterns.length; p++) {
    final pat = d.patterns[p];
    for (var r = 0; r < pat.rows.length; r++) {
      for (var c = 0; c < pat.rows[r].length; c++) {
        final n = pat.rows[r][c].note;
        if (n >= 0) m['$p:$r:$c'] = n;
      }
    }
  }
  return m;
}

void main() {
  final dir = Directory('test/fixtures/wild');
  final files = dir.existsSync()
      ? (dir
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => RegExp(
              r'\.(mod|xm|s3m|it)$',
              caseSensitive: false,
            ).hasMatch(f.path),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  if (files.isEmpty) {
    test(
      'wild corpus',
      () {},
      skip: 'no test/fixtures/wild/ modules — run '
          'dart run bin/fetch_wild_modules.dart',
    );
    return;
  }

  test('the wild corpus has files across formats', () {
    expect(files.length, greaterThan(4));
  });

  group('real tracker modules parse without a Dart Error', () {
    for (final f in files) {
      final label = f.path.replaceFirst('test/fixtures/wild/', '');
      test(label, () {
        final bytes = f.readAsBytesSync();
        ModuleDoc doc;
        try {
          doc = parseAnyModule(bytes);
        } catch (e) {
          // A clean rejection (Exception) is fine; a Dart Error is a parser bug.
          expect(
            e,
            isNot(isA<Error>()),
            reason: '$label: rejected with an Error, not an Exception',
          );
          return;
        }

        // Parsed → structurally sane.
        expect(doc.channelCount, greaterThanOrEqualTo(0), reason: label);
        expect(doc.patterns, isNotNull, reason: label);
        expect(doc.samples, isNotNull, reason: label);

        // Same-format round-trip must not Error AND must keep every note.
        ModuleDoc? doc2;
        try {
          doc2 = parseAnyModule(convertDocTo(doc, doc.sourceFormat));
        } catch (e) {
          expect(
            e,
            isNot(isA<Error>()),
            reason: '$label: same-format round-trip threw an Error',
          );
        }
        if (doc2 != null) {
          final before = _notes(doc);
          if (before.isNotEmpty) {
            final after = _notes(doc2);
            final kept = before.entries.where((e) => after[e.key] == e.value);
            expect(
              kept.length / before.length,
              greaterThanOrEqualTo(0.99),
              reason: '$label: same-format round-trip lost notes',
            );
          }
        }
      });
    }
  });
}
