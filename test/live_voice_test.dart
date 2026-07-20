// LiveVoiceEngine — backend selection, graceful fallback, and persistence.
// (The audio glue in each backend is untested, like the other players.)

import 'dart:typed_data';

import 'package:comet_beat/core/services/live_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRealtime implements LiveVoice {
  @override
  bool get isRealtime => true;
  @override
  Future<void> play(String key, Uint8List wav, {double volume = 1.0}) async {}
  @override
  void invalidate() {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('degrades to classic when no real-time engine is available', () {
    final e = LiveVoiceEngine(); // realtimeFactory → null
    expect(e.mode, LiveVoiceMode.auto);
    expect(e.isRealtimeActive, isFalse);
  });

  test('auto/realtime use the engine; classic forces the pool', () async {
    final e = LiveVoiceEngine(realtimeFactory: _FakeRealtime.new);
    expect(e.isRealtimeActive, isTrue); // auto → engine available

    await e.setMode(LiveVoiceMode.classic);
    expect(e.isRealtimeActive, isFalse);

    await e.setMode(LiveVoiceMode.realtime);
    expect(e.isRealtimeActive, isTrue);
  });

  test('a throwing real-time factory falls back to classic', () {
    final e = LiveVoiceEngine(
      realtimeFactory: () => throw StateError('no engine'),
    );
    expect(e.isRealtimeActive, isFalse);
  });

  test('the chosen mode persists and reloads', () async {
    final e1 = LiveVoiceEngine(realtimeFactory: _FakeRealtime.new);
    await e1.setMode(LiveVoiceMode.classic);

    final e2 = LiveVoiceEngine(realtimeFactory: _FakeRealtime.new);
    await e2.load();
    expect(e2.mode, LiveVoiceMode.classic);
    expect(e2.isRealtimeActive, isFalse);
  });
}
