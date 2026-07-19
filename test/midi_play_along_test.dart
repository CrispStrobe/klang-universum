import 'dart:typed_data';

import 'package:comet_beat/features/games/playalong/midi_play_along_screen.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/songs/user_songs_service.dart';
import 'package:crisp_notation/crisp_notation.dart'
    show Score, TimeSignature, scoreToMidi;
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/game_test_support.dart';

/// A real, parseable SMF (four quarter notes) as a picked file.
XFile _midi(String name) => XFile.fromData(
      scoreToMidi(
        Score.simple(
          notes: 'c4:q d4 e4 f4',
          timeSignature: TimeSignature.fourFour,
        ),
      ),
      name: name,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a button to choose a MIDI file', (tester) async {
    await pumpGame(tester, const MidiPlayAlongScreen());
    expect(find.text('Choose a MIDI file'), findsOneWidget);
  });

  testWidgets('a valid MIDI opens the play-along song screen', (tester) async {
    await pumpGame(
      tester,
      MidiPlayAlongScreen(debugPickFile: () async => _midi('Ode to Joy.mid')),
      extraProviders: [
        ChangeNotifierProvider(create: (_) => UserSongsService()),
      ],
    );

    await tester.tap(find.text('Choose a MIDI file'));
    await tester.pump(); // resolve the pick future + push the route
    await tester
        .pump(const Duration(seconds: 1)); // finish the route transition

    // It parsed cleanly (no error) and opened the play-along song screen.
    expect(find.text("Couldn't read that MIDI file."), findsNothing);
    expect(find.byType(SongScreen), findsOneWidget);
  });

  testWidgets('an unreadable file shows an error and does not navigate', (
    tester,
  ) async {
    await pumpGame(
      tester,
      MidiPlayAlongScreen(
        debugPickFile: () async =>
            XFile.fromData(Uint8List.fromList([1, 2, 3, 4]), name: 'bad.mid'),
      ),
    );

    await tester.tap(find.text('Choose a MIDI file'));
    await tester.pump(); // resolve the pick future
    await tester.pump(); // surface the snackbar

    expect(find.text("Couldn't read that MIDI file."), findsOneWidget);
    expect(find.byType(SongScreen), findsNothing);
  });
}
