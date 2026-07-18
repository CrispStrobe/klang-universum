// BYOK (bring-your-own-key) storage for The Mod Archive's XML API.
//
// The Mod Archive issues an API key **per application** and requires it stay
// **confidential** — so we must NOT ship one (a key baked into a Flutter binary
// is trivially extractable, breaching that term). Instead the ModArchive source
// stays hidden until the user pastes their OWN key (which they request from
// modarchive.org, disclosing their use). The key lives only in local
// SharedPreferences on the device.

import 'package:shared_preferences/shared_preferences.dart';

class ModArchiveKeyStore {
  static const _key = 'modarchive_api_key';

  /// Returns the stored key, or null/empty if none.
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// True if a non-empty key is stored.
  Future<bool> hasKey() async => (await read()) != null;

  /// Stores [key] (trimmed); an empty value clears it.
  Future<void> write(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, trimmed);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
