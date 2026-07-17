// TtsService: narration gating + locale→voice mapping, tested against a fake
// backend (no `flutter_tts` method channel involved).
import 'package:comet_beat/core/services/tts_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements TtsBackend {
  final List<(String, String)> spoken = []; // (text, langCode)
  int stops = 0;

  @override
  Future<void> speak(String text, {required String langCode}) async {
    spoken.add((text, langCode));
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  test('voiceTag maps de→de-DE and everything else→en-US', () {
    expect(TtsService.voiceTag(const Locale('de')), 'de-DE');
    expect(TtsService.voiceTag(const Locale('en')), 'en-US');
    expect(TtsService.voiceTag(const Locale('fr')), 'en-US');
  });

  test('speaks the text in the locale voice when sound is on', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake);
    await tts.speak('Ein gleichmäßiger Puls', locale: const Locale('de'));
    await tts.speak('A steady beat', locale: const Locale('en'));
    expect(fake.spoken, [
      ('Ein gleichmäßiger Puls', 'de-DE'),
      ('A steady beat', 'en-US'),
    ]);
  });

  test('the master sound switch silences narration', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake)..soundOn = false;
    await tts.speak('should stay silent', locale: const Locale('en'));
    expect(fake.spoken, isEmpty);
  });

  test('blank text is a no-op', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake);
    await tts.speak('   ', locale: const Locale('en'));
    expect(fake.spoken, isEmpty);
  });

  test('stop forwards to the backend and clears speaking', () async {
    final fake = _FakeBackend();
    final tts = TtsService(backend: fake);
    await tts.speak('hi', locale: const Locale('en'));
    expect(tts.isSpeaking, isTrue);
    await tts.stop();
    expect(tts.isSpeaking, isFalse);
    expect(fake.stops, greaterThanOrEqualTo(1));
  });
}
