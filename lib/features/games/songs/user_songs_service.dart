// lib/features/games/songs/user_songs_service.dart
//
// Imported content, persisted in SharedPreferences: notation songs (stored
// as MusicXML — the interchange format survives app updates) and ChordPro
// chord sheets (stored as source text).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:partitura/partitura.dart' show Score, scoreFromMusicXml;
import 'package:shared_preferences/shared_preferences.dart';

class ImportedSong {
  final String id;
  final String title;
  final String musicXml;

  const ImportedSong({
    required this.id,
    required this.title,
    required this.musicXml,
  });

  Score get score => scoreFromMusicXml(musicXml);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'xml': musicXml};

  factory ImportedSong.fromJson(Map<String, dynamic> json) => ImportedSong(
        id: json['id'] as String,
        title: json['title'] as String,
        musicXml: json['xml'] as String,
      );
}

class ImportedChordSheet {
  final String id;
  final String title;
  final String source;

  const ImportedChordSheet({
    required this.id,
    required this.title,
    required this.source,
  });

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'source': source};

  factory ImportedChordSheet.fromJson(Map<String, dynamic> json) =>
      ImportedChordSheet(
        id: json['id'] as String,
        title: json['title'] as String,
        source: json['source'] as String,
      );
}

class UserSongsService with ChangeNotifier {
  static const _storageKey = 'user_songs';

  List<ImportedSong> _songs = [];
  List<ImportedChordSheet> _sheets = [];

  List<ImportedSong> get songs => List.unmodifiable(_songs);
  List<ImportedChordSheet> get sheets => List.unmodifiable(_sheets);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final map = json.decode(jsonString) as Map<String, dynamic>;
        _songs = [
          for (final s in (map['songs'] as List? ?? []))
            ImportedSong.fromJson(s as Map<String, dynamic>),
        ];
        _sheets = [
          for (final s in (map['sheets'] as List? ?? []))
            ImportedChordSheet.fromJson(s as Map<String, dynamic>),
        ];
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[USER_SONGS] load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        json.encode({
          'songs': [for (final s in _songs) s.toJson()],
          'sheets': [for (final s in _sheets) s.toJson()],
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[USER_SONGS] save failed: $e');
    }
  }

  void addSong(ImportedSong song) {
    _songs = [..._songs, song];
    notifyListeners();
    _save();
  }

  void addSheet(ImportedChordSheet sheet) {
    _sheets = [..._sheets, sheet];
    notifyListeners();
    _save();
  }

  void removeSong(String id) {
    _songs = _songs.where((s) => s.id != id).toList();
    notifyListeners();
    _save();
  }

  void removeSheet(String id) {
    _sheets = _sheets.where((s) => s.id != id).toList();
    notifyListeners();
    _save();
  }
}
