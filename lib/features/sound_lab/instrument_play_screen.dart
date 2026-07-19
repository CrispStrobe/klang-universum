// Live-play a saved instrument on a full piano keyboard. Tapping a key renders
// that note through the instrument and plays it — a standalone "play your
// instrument" surface, since the tracker (the other consumer) is a separate
// feature. Reached from the "My Instruments" browser.

import 'package:comet_beat/core/audio/tracker_engine.dart'
    show TrackerInstrument;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/my_instruments_sheet.dart'
    show renderInstrumentNote;
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:comet_beat/shared/widgets/piano_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Test seam.
abstract class InstrumentPlayTester {
  int get startMidi;
  void shiftOctave(int delta);
}

class InstrumentPlayScreen extends StatefulWidget {
  const InstrumentPlayScreen({
    required this.instrument,
    required this.name,
    super.key,
  });

  final TrackerInstrument instrument;
  final String name;

  @override
  State<InstrumentPlayScreen> createState() => _InstrumentPlayScreenState();
}

class _InstrumentPlayScreenState extends State<InstrumentPlayScreen>
    implements InstrumentPlayTester {
  // C2 (24) … C6 (84) reachable via octave shift; start at C3.
  int _startMidi = 48;

  @override
  int get startMidi => _startMidi;

  @override
  void shiftOctave(int delta) {
    setState(() {
      _startMidi = (_startMidi + delta * 12).clamp(24, 72);
    });
  }

  void _play(int midi) {
    final pcm = renderInstrumentNote(widget.instrument, midi);
    if (pcm.isEmpty) return;
    context.read<AudioService>().playWavBytes(pcmFloatToWav(pcm));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: l10n.instrumentPlayOctaveDown,
            onPressed: _startMidi > 24 ? () => shiftOctave(-1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: l10n.instrumentPlayOctaveUp,
            onPressed: _startMidi < 72 ? () => shiftOctave(1) : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.instrumentPlayHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 220,
                child: PianoKeyboard(
                  startMidi: _startMidi,
                  whiteKeyCount: 14, // two octaves
                  onKeyTap: _play,
                  showOctaveNumbers: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
