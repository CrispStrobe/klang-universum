// lib/features/games/composition/groove_slots.dart
//
// Local, serverless "save slots" for the Loop Mixer: a named list of groove
// share tokens (the same `KU1.` strings the share sheet copies) kept in
// SharedPreferences, so a kid can keep and revisit their bands. Pure over an
// injected SharedPreferences, so it unit-tests with setMockInitialValues.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One saved groove: a display [name] and its `KU1.` share [token].
class GrooveSlot {
  const GrooveSlot(this.name, this.token);

  final String name;
  final String token;

  Map<String, dynamic> toJson() => {'n': name, 't': token};

  factory GrooveSlot.fromJson(Map<String, dynamic> j) =>
      GrooveSlot(j['n'] as String? ?? '', j['t'] as String? ?? '');
}

/// Persists saved grooves under one SharedPreferences key. Newest first; a save
/// under an existing name replaces it; the list is capped at [maxSlots].
class GrooveSlotsService {
  GrooveSlotsService(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'loop_mixer_slots';
  static const maxSlots = 24;

  /// The saved grooves, newest first (empty on missing/corrupt data — a stored
  /// blob is never allowed to crash the reader).
  List<GrooveSlot> list() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return [
        for (final e in data)
          if (e is Map<String, dynamic>) GrooveSlot.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Saves [token] under [name] (trimmed; empty is ignored), replacing any slot
  /// with the same name and moving it to the front. Returns the new list.
  Future<List<GrooveSlot>> save(String name, String token) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return list();
    final slots = list().where((s) => s.name != trimmed).toList()
      ..insert(0, GrooveSlot(trimmed, token));
    final capped = slots.take(maxSlots).toList();
    await _persist(capped);
    return capped;
  }

  /// Removes the slot named [name]. Returns the new list.
  Future<List<GrooveSlot>> delete(String name) async {
    final slots = list().where((s) => s.name != name).toList();
    await _persist(slots);
    return slots;
  }

  Future<void> _persist(List<GrooveSlot> slots) =>
      _prefs.setString(_key, jsonEncode([for (final s in slots) s.toJson()]));
}
