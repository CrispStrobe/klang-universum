// A persistent "My Instruments" library: named playable instruments saved
// across sessions. Where "My Samples" ([SampleClipStore]) stores raw audio
// clips, this stores a whole [TrackerInstrument] — the shaped Voice Lab voice,
// a picked SoundFont preset, a procedural voice — so it can be recalled and
// played (not just replayed).
//
// The save format is the engine's own instrument JSON codec
// ([instrumentToJsonString]) — the string IS the record, so the store is a thin
// SharedPreferences wrapper. Embedded voices (samples, sfxr, additive, …)
// round-trip synchronously; a referenced SoundFont voice ([isReference]) keeps
// only a file+preset pointer and is resolved with the font bytes elsewhere. The
// encode/decode pair is pure (testable without a platform).

import 'dart:convert';

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/audio/tracker_instrument_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved instrument = a name plus its codec JSON. [source] notes where it
/// came from (e.g. "Voice Lab") for display.
class SavedInstrument {
  const SavedInstrument({
    required this.name,
    required this.json,
    this.source,
  });

  final String name;

  /// The [instrumentToJsonString] payload — the authoritative record.
  final String json;

  final String? source;

  /// The instrument's type tag (e.g. `sample`, `sfxr`, `soundfont_ref`), read
  /// straight from the JSON; `unknown` if it can't be parsed.
  String get kind {
    try {
      final m = jsonDecode(json);
      return (m is Map && m['type'] is String)
          ? m['type'] as String
          : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// True if rebuilding needs the referenced SoundFont file (async), not just
  /// this embedded JSON — resolve those via `resolveInstrumentJson`.
  bool get isReference => kind == 'soundfont_ref';

  /// Rebuilds the instrument from its embedded JSON (synchronous). Returns null
  /// for references (need the font bytes) or malformed data.
  TrackerInstrument? get instrument {
    if (isReference) return null;
    try {
      return instrumentFromJsonString(json);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'json': json,
        if (source != null) 'source': source,
      };

  static SavedInstrument? fromJson(Map<String, dynamic> j) {
    final name = j['name'];
    final json = j['json'];
    if (name is! String || json is! String) return null;
    return SavedInstrument(
      name: name,
      json: json,
      source: j['source'] is String ? j['source'] as String : null,
    );
  }
}

/// Serializes the library to a JSON string.
String encodeInstruments(List<SavedInstrument> items) =>
    jsonEncode([for (final i in items) i.toJson()]);

/// Parses a library; skips malformed entries, returns empty (never throws) for
/// null/blank/invalid input.
List<SavedInstrument> decodeInstruments(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map)
          if (SavedInstrument.fromJson(e.cast<String, dynamic>()) case final s?)
            s,
    ];
  } catch (_) {
    return const [];
  }
}

/// SharedPreferences-backed persistence of the "My Instruments" library.
class InstrumentLibraryStore {
  static const _key = 'sound_lab_instruments';

  Future<List<SavedInstrument>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeInstruments(prefs.getString(_key));
  }

  /// Adds [inst]; a save under an existing name overwrites it. Newest last.
  Future<List<SavedInstrument>> save(SavedInstrument inst) async {
    final list = [...await load()]..removeWhere((x) => x.name == inst.name);
    list.add(inst);
    await _write(list);
    return list;
  }

  Future<List<SavedInstrument>> delete(String name) async {
    final list = [...await load()]..removeWhere((x) => x.name == name);
    await _write(list);
    return list;
  }

  Future<void> _write(List<SavedInstrument> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encodeInstruments(list));
  }
}
