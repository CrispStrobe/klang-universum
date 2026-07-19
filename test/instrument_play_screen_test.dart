// InstrumentPlayScreen — the live-play surface. Builds the shared piano and
// shifts octaves within range (24..72). Tapping keys plays audio (not exercised
// here — that needs AudioService); the seam covers the pure state.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/features/sound_lab/instrument_play_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

SampleInstrument _voice() {
  final pcm = Float64List(2048);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = 0.4 * math.sin(2 * math.pi * 220 * i / 44100);
  }
  return SampleInstrument('v', pcm);
}

InstrumentPlayTester _screen(WidgetTester t) =>
    t.state<State<InstrumentPlayScreen>>(find.byType(InstrumentPlayScreen))
        as InstrumentPlayTester;

void main() {
  testWidgets('builds a keyboard for the instrument', (tester) async {
    await tester.pumpWidget(
      _app(InstrumentPlayScreen(instrument: _voice(), name: 'My Voice')),
    );
    expect(find.text('My Voice'), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsOneWidget);
    expect(_screen(tester).startMidi, 48); // starts at C3
  });

  testWidgets('octave shift moves the range and clamps at the ends',
      (tester) async {
    await tester.pumpWidget(
      _app(InstrumentPlayScreen(instrument: _voice(), name: 'v')),
    );
    final s = _screen(tester);

    s.shiftOctave(1);
    expect(s.startMidi, 60);
    s.shiftOctave(-1);
    s.shiftOctave(-1);
    expect(s.startMidi, 36);
    // clamps at 24 (won't go below C1)
    for (var i = 0; i < 5; i++) {
      s.shiftOctave(-1);
    }
    expect(s.startMidi, 24);
    // clamps at 72 (top)
    for (var i = 0; i < 10; i++) {
      s.shiftOctave(1);
    }
    expect(s.startMidi, 72);
  });
}
