// lib/core/services/progress_service.dart
//
// Per-game progression, persisted in SharedPreferences: best stars, best
// score, play count. Drives the stars shown on game tiles and the
// star-based difficulty scaling inside games (docs/PLAN.md).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameProgress {
  final int bestStars; // 0..3
  final int bestScore;
  final int plays;

  const GameProgress({
    this.bestStars = 0,
    this.bestScore = 0,
    this.plays = 0,
  });

  Map<String, dynamic> toJson() =>
      {'stars': bestStars, 'score': bestScore, 'plays': plays};

  factory GameProgress.fromJson(Map<String, dynamic> json) => GameProgress(
        bestStars: (json['stars'] as int?) ?? 0,
        bestScore: (json['score'] as int?) ?? 0,
        plays: (json['plays'] as int?) ?? 0,
      );
}

class ProgressService with ChangeNotifier {
  ProgressService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _storageKey = 'game_progress';
  static const _daysKey = 'practice_days';

  /// Clock, injectable for tests.
  final DateTime Function() _now;

  Map<String, GameProgress> _byGame = {};

  /// Days on which at least one game was finished, as `YYYY-MM-DD` keys.
  Set<String> _practiceDays = {};

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        _byGame = jsonMap.map(
          (key, value) => MapEntry(
            key,
            GameProgress.fromJson(value as Map<String, dynamic>),
          ),
        );
      }
      final days = prefs.getStringList(_daysKey);
      if (days != null) _practiceDays = days.toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('[PROGRESS] load failed: $e');
      _byGame = {};
      _practiceDays = {};
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        json.encode(_byGame.map((key, v) => MapEntry(key, v.toJson()))),
      );
      await prefs.setStringList(_daysKey, _practiceDays.toList());
    } catch (e) {
      if (kDebugMode) debugPrint('[PROGRESS] save failed: $e');
    }
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Records a finished game; keeps the best stars/score, counts plays, and
  /// marks today as a practice day (feeds the streak).
  void recordResult(String gameId, {required int score, required int stars}) {
    final old = _byGame[gameId] ?? const GameProgress();
    _byGame[gameId] = GameProgress(
      bestStars: stars > old.bestStars ? stars : old.bestStars,
      bestScore: score > old.bestScore ? score : old.bestScore,
      plays: old.plays + 1,
    );
    _practiceDays.add(_dayKey(_now()));
    notifyListeners();
    _save();
  }

  /// Whether a game was finished on [day].
  bool practicedOn(DateTime day) => _practiceDays.contains(_dayKey(day));

  /// Date-only "today" per the injected clock (used for streak + calendar).
  DateTime get today => DateTime(_now().year, _now().month, _now().day);

  /// Consecutive practice days ending today (or yesterday, so the streak
  /// doesn't read as broken before today's first session).
  int get currentStreak {
    var day =
        practicedOn(today) ? today : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (practicedOn(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  GameProgress progressFor(String gameId) =>
      _byGame[gameId] ?? const GameProgress();

  /// Best stars for [gameId] (0 if never finished).
  int starsFor(String gameId) => progressFor(gameId).bestStars;

  int get totalStars => _byGame.values.fold(0, (sum, p) => sum + p.bestStars);
}
