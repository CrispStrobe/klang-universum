// lib/core/services/debug_service.dart
//
// A tiny developer/parent escape hatch matching the sibling apps (voc,
// space_math_academy): tap the app title seven times to unlock every module
// from the start, so all games are freely choosable for testing or for a child
// who wants to roam. Persisted, and switchable back off in Settings.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DebugService with ChangeNotifier {
  static const _unlockAllKey = 'debug_unlock_all';

  bool _unlockAll = false;

  /// When true, the module unlock gating is bypassed — every module is open.
  bool get unlockAll => _unlockAll;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _unlockAll = prefs.getBool(_unlockAllKey) ?? false;
    notifyListeners();
  }

  Future<void> setUnlockAll(bool value) async {
    if (_unlockAll == value) return;
    _unlockAll = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unlockAllKey, value);
  }
}
