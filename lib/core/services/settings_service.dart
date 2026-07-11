// lib/core/services/settings_service.dart
//
// App settings, persisted in SharedPreferences: locale override (null = follow
// the system, the default) and the note-naming convention.

import 'package:flutter/material.dart';
import 'package:klang_universum/core/note_naming.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService with ChangeNotifier {
  static const _localeKey = 'app_locale';
  static const _noteNamingKey = 'note_naming';

  Locale? _locale;
  NoteNaming _noteNaming = NoteNaming.auto;

  /// Forced app locale; null follows the system locale.
  Locale? get locale => _locale;

  /// How note letters are spelled (auto follows the app language).
  NoteNaming get noteNaming => _noteNaming;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    _locale = (code == null || code.isEmpty) ? null : Locale(code);
    final naming = prefs.getString(_noteNamingKey);
    _noteNaming = NoteNaming.values.asNameMap()[naming] ?? NoteNaming.auto;
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale?.languageCode ?? '');
  }

  Future<void> setNoteNaming(NoteNaming naming) async {
    _noteNaming = naming;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_noteNamingKey, naming.name);
  }
}
