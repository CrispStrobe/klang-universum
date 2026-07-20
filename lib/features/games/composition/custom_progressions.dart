// lib/features/games/composition/custom_progressions.dart
//
// Persisted "make your own harmony" presets for the Loop Mixer (LM-UX7). A
// custom [Progression] is just a list of [ChordDegree]s the kid picked; every
// degree the app offers (I · IV · V · vi) is consonant with the C-pentatonic
// melodies, so ANY combination stays in tune (the colour-melody invariant holds
// for free). Stored as one SharedPreferences string; the encode/decode pair is
// pure so it's testable without a platform.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serialise custom progressions as `i0,i1,…;i0,i1,…` where each number is an
/// index into [ChordDegree.values].
String encodeCustomProgressions(List<Progression> ps) => ps
    .map((p) => p.degrees.map(ChordDegree.values.indexOf).join(','))
    .join(';');

/// Parse [encodeCustomProgressions] output; skips malformed entries, never
/// throws, and re-assigns stable `custom-N` ids by position.
List<Progression> decodeCustomProgressions(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final out = <Progression>[];
  for (final part in raw.split(';')) {
    if (part.trim().isEmpty) continue;
    final degrees = <ChordDegree>[];
    var ok = true;
    for (final tok in part.split(',')) {
      final i = int.tryParse(tok.trim());
      if (i == null || i < 0 || i >= ChordDegree.values.length) {
        ok = false;
        break;
      }
      degrees.add(ChordDegree.values[i]);
    }
    if (ok && degrees.length >= 2) {
      out.add(Progression('custom-${out.length}', degrees));
    }
  }
  return out;
}

/// SharedPreferences-backed store for the kid's own harmonies.
class CustomProgressionStore {
  static const _key = 'loop_mixer_custom_progressions';

  Future<List<Progression>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeCustomProgressions(prefs.getString(_key));
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Progression> ps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encodeCustomProgressions(ps));
    } catch (_) {
      // Best-effort; the in-memory list still applies this session.
    }
  }
}
