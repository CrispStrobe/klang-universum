// lib/core/services/live_voice.dart
//
// The live play-in voice behind a swappable backend, so a kid can choose how
// the keyboard/pads sound:
//
//   • CLASSIC  — the audioplayers VoicePool (always available). Polyphonic, but
//                each tap re-decodes a WAV, so there's some latency.
//   • REALTIME — a low-latency engine (wired in R2 via flutter_soloud): a source
//                is decoded once and replayed instantly, with per-tap volume.
//
// [LiveVoiceEngine] picks the backend from the user's [LiveVoiceMode] setting
// and gracefully degrades to CLASSIC whenever the real-time engine isn't
// available (unsupported platform, init failure, or simply not built yet). The
// persisted preference is read/written best-effort — a missing prefs plugin
// (e.g. in a headless test) never breaks playback.

import 'package:comet_beat/core/services/voice_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the live keyboard/pad voice should be driven.
enum LiveVoiceMode {
  /// Use the real-time engine when available, else the classic pool.
  auto,

  /// Always the classic audioplayers pool.
  classic,

  /// Force the real-time engine (falls back to classic if unavailable).
  realtime,
}

LiveVoiceMode _modeFromName(String? name) => LiveVoiceMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => LiveVoiceMode.auto,
    );

/// One swappable live-voice backend.
abstract class LiveVoice {
  /// True when this is a genuine low-latency engine (not the classic pool).
  bool get isRealtime;

  /// Play [wav] (identified by [key] so a backend can cache the decoded source)
  /// at [volume] (0..1+, the play-in velocity).
  Future<void> play(String key, Uint8List wav, {double volume = 1.0});

  /// Drop any cached sources — call when the sound behind the keys changes.
  void invalidate();

  void dispose();
}

/// The always-available backend: the audioplayers voice pool.
class PooledLiveVoice implements LiveVoice {
  final VoicePool _pool = VoicePool();

  @override
  bool get isRealtime => false;

  @override
  Future<void> play(String key, Uint8List wav, {double volume = 1.0}) =>
      _pool.play(wav, volume: volume);

  @override
  void invalidate() {}

  @override
  void dispose() => _pool.dispose();
}

/// Builds the real-time backend when one is available. R1 has none (returns
/// null → always degrades to [PooledLiveVoice]); R2 sets this to the
/// flutter_soloud implementation. Kept as a hook so the wiring, fallback, and
/// UI can ship and be tested before the native dependency lands.
typedef RealtimeVoiceFactory = LiveVoice? Function();

/// Picks and manages the active [LiveVoice] from the user's [LiveVoiceMode],
/// degrading to CLASSIC whenever REALTIME isn't available.
class LiveVoiceEngine {
  LiveVoiceEngine({RealtimeVoiceFactory? realtimeFactory})
      : _realtimeFactory = realtimeFactory ?? (() => null);

  static const _prefKey = 'perform_audio_mode';

  final RealtimeVoiceFactory _realtimeFactory;
  LiveVoiceMode _mode = LiveVoiceMode.auto;
  LiveVoice? _active;

  LiveVoiceMode get mode => _mode;

  /// The backend actually in use right now (built lazily on first need).
  LiveVoice get _voice => _active ??= _select();

  /// True when the real-time engine is the one actually playing.
  bool get isRealtimeActive => _voice.isRealtime;

  LiveVoice _select() {
    if (_mode != LiveVoiceMode.classic) {
      final rt = _tryRealtime();
      if (rt != null) return rt;
    }
    return PooledLiveVoice();
  }

  LiveVoice? _tryRealtime() {
    try {
      return _realtimeFactory();
    } catch (e) {
      if (kDebugMode) debugPrint('[LIVEVOICE] realtime unavailable: $e');
      return null;
    }
  }

  void _rebuild() {
    _active?.dispose();
    _active = _select();
  }

  /// Load the persisted mode (best-effort).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _modeFromName(prefs.getString(_prefKey));
    } catch (_) {
      _mode = LiveVoiceMode.auto;
    }
    _rebuild();
  }

  Future<void> setMode(LiveVoiceMode mode) async {
    _mode = mode;
    _rebuild();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {
      // Persisting is best-effort; the in-memory mode still applies.
    }
  }

  Future<void> play(String key, Uint8List wav, {double volume = 1.0}) =>
      _voice.play(key, wav, volume: volume);

  void invalidate() => _active?.invalidate();

  void dispose() {
    _active?.dispose();
    _active = null;
  }
}
