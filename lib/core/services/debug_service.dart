// lib/core/services/debug_service.dart
//
// A tiny developer/parent escape hatch matching the sibling apps (voc,
// space_math_academy): tapping the app title seven times reveals a hidden
// Debug section in Settings ([menuEnabled]). From there a switch unlocks every
// module ([unlockAll]) so all games are freely choosable. Both flags persist.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DebugService with ChangeNotifier {
  static const _menuKey = 'debug_menu_enabled';
  static const _unlockAllKey = 'debug_unlock_all';

  bool _menuEnabled = false;
  bool _unlockAll = false;

  /// Whether the hidden Debug section (in Settings) is revealed. Turned on by
  /// seven taps on the app title.
  bool get menuEnabled => _menuEnabled;

  /// When true, the module unlock gating is bypassed — every module is open.
  /// Only reachable once [menuEnabled].
  bool get unlockAll => _unlockAll;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _menuEnabled = prefs.getBool(_menuKey) ?? false;
    _unlockAll = prefs.getBool(_unlockAllKey) ?? false;
    notifyListeners();
  }

  Future<void> enableMenu() async {
    if (_menuEnabled) return;
    _menuEnabled = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_menuKey, true);
  }

  Future<void> setUnlockAll(bool value) async {
    if (_unlockAll == value) return;
    _unlockAll = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unlockAllKey, value);
  }
}
