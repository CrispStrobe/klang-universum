// lib/core/services/tts_service.dart
//
// Text-to-speech narration for the lessons/primers (and, later, game how-to
// text). A pre-reader (6–8yo) can HEAR a lesson before they can read it, and it
// makes the app accessible.
//
// Design: the plugin (`flutter_tts` — platform AVSpeechSynthesizer / Android TTS
// / web SpeechSynthesis, all on-device + offline + free) sits behind a
// [TtsBackend] interface, so (a) tests inject a fake with no method channel, and
// (b) a higher-quality neural backend (CrispTTS / Kokoro-ONNX via
// onnx_runtime_dart) can slot in later without touching call sites. This is the
// ONLY file that imports the TTS plugin.
//
// Narration follows the master sound switch ([soundOn], mirrored from
// SettingsService like AudioService): sound off ⇒ the app is silent, narration
// included. Speaking is best-effort — a platform with no voice for the locale
// just stays quiet rather than throwing.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_tts/flutter_tts.dart';

/// The speech engine behind [TtsService]. Swappable for tests and for a future
/// neural backend.
abstract class TtsBackend {
  /// Speak [text] in the given BCP-47 [langCode] (e.g. `de-DE`, `en-US`).
  /// Should interrupt any in-progress utterance.
  Future<void> speak(String text, {required String langCode});

  /// Stop any in-progress utterance.
  Future<void> stop();
}

/// The real backend, driving the `flutter_tts` plugin. Every call is guarded:
/// on a platform/locale without a voice it degrades to silence, never a crash.
class FlutterTtsBackend implements TtsBackend {
  FlutterTtsBackend() {
    // A calm, child-friendly cadence. Rates are best-effort per platform.
    _tts
      ..setSpeechRate(0.45)
      ..setVolume(1.0)
      ..setPitch(1.0);
  }

  final FlutterTts _tts = FlutterTts();
  String? _lang;

  @override
  Future<void> speak(String text, {required String langCode}) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      if (_lang != langCode) {
        await _tts.setLanguage(langCode);
        _lang = langCode;
      }
      await _tts.speak(text);
    } catch (_) {
      // No voice / channel unavailable (e.g. headless, or a locale the OS lacks)
      // — stay silent rather than surface an error to a child.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // ignore
    }
  }
}

class TtsService with ChangeNotifier {
  TtsService({TtsBackend? backend}) : _backend = backend ?? FlutterTtsBackend();

  final TtsBackend _backend;

  /// Master sound switch, mirrored from SettingsService (see main.dart). When
  /// off, narration is silent along with the rest of the app.
  bool soundOn = true;

  /// True while an utterance has been requested and not yet stopped. Purely for
  /// UI affordance (e.g. a speaking indicator); best-effort, not frame-accurate.
  bool get isSpeaking => _speaking;
  bool _speaking = false;

  /// Map an app [Locale] to a platform BCP-47 voice tag. German → `de-DE`,
  /// everything else → `en-US` (the app ships de + en).
  static String voiceTag(Locale locale) =>
      locale.languageCode == 'de' ? 'de-DE' : 'en-US';

  /// Narrate [text] in [locale]. No-op when the master sound switch is off or
  /// the text is blank. Interrupts any current utterance.
  Future<void> speak(String text, {required Locale locale}) async {
    if (!soundOn || text.trim().isEmpty) return;
    _speaking = true;
    notifyListeners();
    await _backend.speak(text, langCode: voiceTag(locale));
  }

  /// Stop narrating (e.g. the sheet was dismissed or the page changed).
  Future<void> stop() async {
    if (_speaking) {
      _speaking = false;
      notifyListeners();
    }
    await _backend.stop();
  }

  @override
  void dispose() {
    _backend.stop();
    super.dispose();
  }
}
