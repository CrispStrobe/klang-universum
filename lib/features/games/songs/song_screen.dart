// lib/features/games/songs/song_screen.dart
//
// The song player: full notation with lyrics across wrapped systems
// (partitura MultiSystemView), a play button, and a karaoke-style cursor —
// the sounding note highlights in sync (repaint-only per the partitura
// contract). Tapping any note plays it.

import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart'
    show MultiSystemView, NoteElement, PartituraTheme;
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../l10n/app_localizations.dart';
import 'song_book.dart';

class SongScreen extends StatefulWidget {
  final Song song;

  const SongScreen({super.key, required this.song});

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  String? _highlightedId;
  bool _playing = false;
  int _playToken = 0; // invalidates a running play loop

  late final Map<String, int> _midiById = {
    for (final measure in widget.song.score.measures)
      for (final element in measure.elements)
        if (element is NoteElement && element.id != null)
          element.id!: element.pitches.first.midiNumber,
  };

  Future<void> _play() async {
    final token = ++_playToken;
    final audio = context.read<AudioService>();
    setState(() => _playing = true);

    // One synthesized render of the whole melody...
    audio.playSequence([
      for (final (_, midi, ms) in widget.song.playback) (midi, ms),
    ]);
    // ...while the cursor walks the notation in the same rhythm.
    for (final (id, _, ms) in widget.song.playback) {
      if (!mounted || token != _playToken) return;
      setState(() => _highlightedId = id);
      await Future.delayed(Duration(milliseconds: ms));
    }
    if (!mounted || token != _playToken) return;
    setState(() {
      _highlightedId = null;
      _playing = false;
    });
  }

  void _stop() {
    _playToken++;
    context.read<AudioService>().playMidiNote(0, ms: 1); // cuts playback
    setState(() {
      _highlightedId = null;
      _playing = false;
    });
  }

  @override
  void dispose() {
    _playToken++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(widget.song.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: MultiSystemView(
                      score: widget.song.score,
                      staffSpace: 11,
                      theme: PartituraTheme.kids,
                      highlightedIds: {
                        if (_highlightedId != null) _highlightedId!,
                      },
                      onElementTap: (id) {
                        final midi = _midiById[id];
                        if (midi != null) {
                          context
                              .read<AudioService>()
                              .playMidiNote(midi, ms: 500);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _playing ? _stop : _play,
                icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                label: Text(
                    _playing ? l10n.songStop : l10n.myMelodyPlay),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SongListScreen extends StatelessWidget {
  const SongListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameSongBook)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final song in kSongs)
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: const CircleAvatar(child: Icon(Icons.music_note)),
                title: Text(song.title),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => SongScreen(song: song)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
