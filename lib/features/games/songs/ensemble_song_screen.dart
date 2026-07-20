// lib/features/games/songs/ensemble_song_screen.dart
//
// A public-domain song for 2–5 voices: each voice is drawn on its own staff
// (stacked), and Play mixes them together (a real canon/part-song) via
// AudioService.playMixedTimedChords. Read-only — the single-voice SongScreen
// stays the place for karaoke/play-along/analysis; this one shows the ensemble.

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/games/songs/song_book.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/score_theme.dart';
import 'package:crisp_notation/crisp_notation.dart' show MultiSystemView;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EnsembleSongScreen extends StatefulWidget {
  const EnsembleSongScreen({super.key, required this.song});

  final EnsembleSong song;

  @override
  State<EnsembleSongScreen> createState() => _EnsembleSongScreenState();
}

class _EnsembleSongScreenState extends State<EnsembleSongScreen> {
  bool _playing = false;
  int _token = 0;

  Future<void> _play() async {
    final audio = context.read<AudioService>();
    final token = ++_token;
    setState(() => _playing = true);
    // One part per voice, rest-aware so staggered canon entries line up.
    final parts = [
      for (final v in widget.song.voices)
        ensembleVoicePlayback(v.score, quarterMs: widget.song.quarterMs),
    ];
    await audio.playMixedTimedChords(parts);
    if (!mounted || token != _token) return;
    setState(() => _playing = false);
  }

  void _stop() {
    _token++;
    context.read<AudioService>().stop();
    setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final song = widget.song;
    return Scaffold(
      appBar: AppBar(title: Text(song.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ensembleVoiceCount(song.voices.length),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _playing ? null : _play,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.myMelodyPlay),
                ),
                if (_playing)
                  OutlinedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.songStop),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final voice in song.voices) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  voice.name,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: MultiSystemView(
                    score: voice.score,
                    staffSpace: 11,
                    theme: kidsScoreTheme,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
