// The transcription-engine config service persists quality + per-step backend
// choices across restarts, and starts from sensible defaults.

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:comet_beat/core/audio/transcription/f0_decode_options.dart';
import 'package:comet_beat/core/services/transcription_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    F0DecodeOptions.viterbi = null;
  });

  test('defaults to balanced quality + all-auto backends', () async {
    final svc = TranscriptionConfigService();
    await svc.load();
    expect(svc.config.quality, ModelQuality.balanced);
    expect(svc.config.backendFor(TranscriptionStep.f0), Backend.auto);
  });

  test('persists quality + a per-step backend across a reload', () async {
    final a = TranscriptionConfigService();
    await a.load();
    await a.setQuality(ModelQuality.accurate);
    await a.setBackend(TranscriptionStep.f0, Backend.crispasr);

    // A fresh service reads the same SharedPreferences.
    final b = TranscriptionConfigService();
    await b.load();
    expect(b.config.quality, ModelQuality.accurate);
    expect(b.config.backendFor(TranscriptionStep.f0), Backend.crispasr);
    expect(b.config.backendFor(TranscriptionStep.separation), Backend.auto);
  });

  test('notifies listeners on change', () async {
    final svc = TranscriptionConfigService();
    await svc.load();
    var notified = 0;
    svc.addListener(() => notified++);
    await svc.setQuality(ModelQuality.fast);
    expect(notified, greaterThan(0));
  });

  test('F0-Viterbi persists and drives the process-wide override', () async {
    expect(F0DecodeOptions.viterbi, isNull); // default → defer to env gate

    final a = TranscriptionConfigService();
    await a.load();
    await a.setF0Viterbi(true);
    expect(a.config.f0Viterbi, isTrue);
    expect(F0DecodeOptions.viterbi, isTrue); // forces it on for the decoders

    // Persists across a reload, and re-applies the override on load.
    F0DecodeOptions.viterbi = null;
    final b = TranscriptionConfigService();
    await b.load();
    expect(b.config.f0Viterbi, isTrue);
    expect(F0DecodeOptions.viterbi, isTrue);

    // Turning it off defers to the env gate again (override cleared).
    await b.setF0Viterbi(false);
    expect(F0DecodeOptions.viterbi, isNull);
  });
}
