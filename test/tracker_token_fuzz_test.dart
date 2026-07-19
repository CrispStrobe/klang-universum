// Structure-aware fuzzer for the CBS1. share-token decoder. Dumb byte fuzzing
// can't reach this code — a random string almost never forms a valid
// base64→zlib→utf8→JSON envelope. So this builds a REAL token from a real
// song's JSON, then mutates leaf field values to hostile-but-typed inputs
// (huge ints, negatives, wrong types, null, empty collections) and re-encodes,
// exercising every field reader in the decoder. The contract:
//   * tryTrackerSongFromToken (the UI paste path) NEVER throws and NEVER OOMs —
//     it returns null or a song for any input; and
//   * trackerSongFromToken throws only a TrackerSongCodecException (an
//     Exception), never a bare Error.
// This is the class of bug that surfaced the unbounded-`rows` allocation bomb;
// the fuzzer guards its siblings. Pure Dart.

import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart' show ZLibEncoder;
import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/audio/tracker_song.dart';
import 'package:comet_beat/core/audio/tracker_song_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small but structurally rich song so the JSON has many mutable fields.
TrackerSong _song() {
  final s = TrackerSong(timing: const TrackerTiming(rows: 8));
  s.engine.setCell(0, 0, const TrackerCell(midi: 60, volume: 0.8));
  s.engine.setCell(0, 2, const TrackerCell(midi: 64, fxCmd: 0x1, fxParam: 4));
  s.engine.setCell(1, 1, const TrackerCell(midi: 48, instrument: 1));
  s.instruments.add(const AdditiveInstrument('cello', Instrument.cello));
  s.addPattern(cloneCurrent: true);
  s.addToOrder(1);
  s.syncCurrent();
  return s;
}

/// Hostile leaf values — the kinds that break unguarded field readers.
const _hostile = <Object?>[
  2000000000, // allocation-bomb / overflow int
  -2000000000,
  -1,
  0,
  9999999999999, // > 32-bit
  1.5e308, // huge double
  double.nan,
  'not-a-number',
  '',
  null,
  <Object?>[],
  <String, Object?>{},
  true,
];

/// Walks [node], collecting (parent, key/index) references to every leaf.
void _collectLeaves(
  Object? node,
  List<void Function(Object?)> setters,
) {
  if (node is Map) {
    for (final k in node.keys.toList()) {
      final v = node[k];
      if (v is Map || v is List) {
        _collectLeaves(v, setters);
      } else {
        setters.add((nv) => node[k] = nv);
      }
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      final v = node[i];
      if (v is Map || v is List) {
        _collectLeaves(v, setters);
      } else {
        final idx = i;
        setters.add((nv) => node[idx] = nv);
      }
    }
  }
}

String _tokenOf(Object? json) {
  final bytes = utf8.encode(jsonEncode(json));
  final z = const ZLibEncoder().encodeBytes(bytes);
  return 'CBS1.${base64UrlEncode(z)}';
}

void main() {
  test('mutated tokens never OOM or throw a bare Error', () {
    final baseJson = trackerSongToJson(_song());
    final rng = Random(424242);

    for (var iter = 0; iter < 300; iter++) {
      // Deep copy so each iteration mutates a fresh tree.
      final tree = jsonDecode(jsonEncode(baseJson));
      final setters = <void Function(Object?)>[];
      _collectLeaves(tree, setters);
      if (setters.isEmpty) continue;

      // Corrupt 1–4 random leaves with hostile values.
      final n = 1 + rng.nextInt(4);
      for (var m = 0; m < n; m++) {
        setters[rng.nextInt(setters.length)](
          _hostile[rng.nextInt(_hostile.length)],
        );
      }

      final String token;
      try {
        token = _tokenOf(tree);
      } catch (_) {
        continue; // a value jsonEncode can't handle (e.g. NaN) — skip
      }

      // The UI paste path must never throw and never OOM.
      expect(tryTrackerSongFromToken(token), anyOf(isNull, isNotNull));

      // The throwing decoder must map every failure to its typed Exception.
      try {
        trackerSongFromToken(token);
      } on Exception {
        // ok — the contract
      } catch (e) {
        fail('trackerSongFromToken threw a non-Exception ${e.runtimeType}: $e');
      }
    }
  });
}
