// The full-palette "Instrument sound" voice: id→voice resolution, the settings
// persistence + migration from the legacy 4-way enum, and the picker UI (search
// + category filter + choose-on-long-press).

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/voice_options.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/settings_service.dart';
import 'package:comet_beat/features/settings/screens/voice_picker_sheet.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('resolveVoiceSync', () {
    test('additive ids map to the enum with NO override', () {
      final r = resolveVoiceSync('cello');
      expect(r.instrument, Instrument.cello);
      expect(r.voice, isNull); // classic additive path
    });

    test('a procedural id builds a voice override (piano fallback timbre)', () {
      final r = resolveVoiceSync('blip');
      expect(r.instrument, Instrument.piano);
      expect(r.voice, isNotNull);
    });

    test('an unknown id falls back to plain piano', () {
      final r = resolveVoiceSync('nonsense');
      expect(r.instrument, Instrument.piano);
      expect(r.voice, isNull);
    });
  });

  group('SettingsService voice', () {
    test('selecting a procedural voice sets the override + persists', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsService();
      await s.load();
      await s.setVoiceId('pluck');
      expect(s.voiceId, 'pluck');
      expect(s.voice, isNotNull);

      // reloads from disk
      final s2 = SettingsService();
      await s2.load();
      expect(s2.voiceId, 'pluck');
      expect(s2.voice, isNotNull);
    });

    test('migrates from the legacy enum key when voice_id is absent', () async {
      SharedPreferences.setMockInitialValues({'instrument': 'flute'});
      final s = SettingsService();
      await s.load();
      expect(s.voiceId, 'flute');
      expect(s.instrument, Instrument.flute);
      expect(s.voice, isNull);
    });

    test('setInstrument still works (routes through voiceId)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsService();
      await s.load();
      await s.setInstrument(Instrument.cello);
      expect(s.voiceId, 'cello');
      expect(s.instrument, Instrument.cello);
      expect(s.voice, isNull);
    });
  });

  group('VoicePickerSheet', () {
    Widget host() => MultiProvider(
          providers: [Provider<AudioService>(create: (_) => AudioService())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: VoicePickerSheet(currentId: 'piano')),
          ),
        );

    testWidgets('lists procedural voices beyond the four additive', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      expect(find.text('Piano'), findsOneWidget); // an additive voice
      // more than the four classic additive voices are offered (the rest are
      // below the viewport; the filter/search tests reach them).
      expect(find.byType(ListTile).evaluate().length, greaterThan(4));
    });

    testWidgets('the Chiptune filter narrows to chiptune voices', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'Chiptune'));
      await t.pumpAndSettle();
      expect(find.text('Piano'), findsNothing); // tonal, filtered out
      expect(find.text('Blip'), findsWidgets); // chiptune, kept
    });

    testWidgets('search narrows the list', (t) async {
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'pluck');
      await t.pumpAndSettle();
      expect(find.textContaining('Pluck'), findsWidgets);
      expect(find.text('Piano'), findsNothing);
    });

    testWidgets('long-press chooses a voice (pops its id)', (t) async {
      String? picked;
      await t.pumpWidget(
        MultiProvider(
          providers: [Provider<AudioService>(create: (_) => AudioService())],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async =>
                      picked = await showVoicePicker(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.longPress(find.text('Blip').first);
      await t.pumpAndSettle();
      expect(picked, 'blip');
    });
  });
}
