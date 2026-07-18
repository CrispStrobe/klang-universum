// A persistent "My Sounds" store for the Sound Lab: save the sounds you make
// and recall them across sessions. Built entirely on SfxParams' own JSON
// serialization (no engine dependency) + SharedPreferences.
//
// This is the Sound Lab's OWN user-preset store — distinct from the tracker's
// built-in instrument catalog. The encode/decode pair is pure (testable
// without a platform) and the store wraps it over SharedPreferences.

import 'dart:convert';

import 'package:comet_beat/features/sound_lab/sfx_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A named saved sound = a label + the params that render it.
class SoundPreset {
  const SoundPreset(this.name, this.params);
  final String name;
  final SfxParams params;

  Map<String, dynamic> toJson() => {'name': name, 'params': params.toJson()};

  static SoundPreset? fromJson(Map<String, dynamic> j) {
    final name = j['name'];
    final params = j['params'];
    if (name is! String || params is! Map) return null;
    return SoundPreset(
      name,
      SfxParams.fromJson(params.cast<String, dynamic>()),
    );
  }
}

/// Serializes a preset list to a JSON string.
String encodePresets(List<SoundPreset> presets) =>
    jsonEncode([for (final p in presets) p.toJson()]);

/// Parses a preset list from a JSON string; skips any malformed entry and
/// returns an empty list for null/blank/invalid input (never throws).
List<SoundPreset> decodePresets(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map)
          if (SoundPreset.fromJson(e.cast<String, dynamic>()) case final p?) p,
    ];
  } catch (_) {
    return const [];
  }
}

/// SharedPreferences-backed persistence of the Sound Lab's saved sounds.
class SoundPresetStore {
  static const _key = 'sound_lab_presets';

  Future<List<SoundPreset>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return decodePresets(prefs.getString(_key));
  }

  /// Saves [preset], replacing any existing one with the same name (a save
  /// under an existing name overwrites it). Newest is kept last.
  Future<List<SoundPreset>> save(SoundPreset preset) async {
    final list = [...await load()]..removeWhere((p) => p.name == preset.name);
    list.add(preset);
    await _write(list);
    return list;
  }

  Future<List<SoundPreset>> delete(String name) async {
    final list = [...await load()]..removeWhere((p) => p.name == name);
    await _write(list);
    return list;
  }

  Future<void> _write(List<SoundPreset> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encodePresets(list));
  }
}
