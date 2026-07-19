// lib/features/games/playalong/midi_play_along_screen.dart
//
// "Play along to a MIDI file" — pick any `.mid` and turn it straight into a
// moving-score play/sing-along. Every piece already exists: `scoreFromMidi`
// parses the file and `SongScreen.fromScore` derives the play + sing charts and
// renders the note-highway. This screen is only the one-tap bridge — the Song
// Book *imports* a MIDI (and saves it); here you play it immediately.

import 'package:comet_beat/features/games/songs/import/midi_import.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

class MidiPlayAlongScreen extends StatefulWidget {
  const MidiPlayAlongScreen({super.key, this.debugPickFile});

  /// Test seam: returns the picked file instead of showing the OS picker.
  final Future<XFile?> Function()? debugPickFile;

  @override
  State<MidiPlayAlongScreen> createState() => _MidiPlayAlongScreenState();
}

class _MidiPlayAlongScreenState extends State<MidiPlayAlongScreen> {
  bool _busy = false;

  Future<void> _pick() async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final file = await (widget.debugPickFile?.call() ??
          openFile(
            acceptedTypeGroups: [
              const XTypeGroup(label: 'MIDI', extensions: ['mid', 'midi']),
            ],
          ));
      if (file == null || !mounted) return;
      final score = scoreFromMidi(await file.readAsBytes());
      if (score.measures.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(l.midiPlayAlongFailed)));
        return;
      }
      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SongScreen.fromScore(
            title: _titleFrom(file.name),
            score: score,
          ),
        ),
      );
    } catch (_) {
      // scoreFromMidi throws FormatException on anything it can't read.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l.midiPlayAlongFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A friendly song title from a file name: strip any path and the extension.
  static String _titleFrom(String fileName) {
    final base = fileName.split('/').last.split(r'\').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.gameMidiPlayAlong)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.piano,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l.midiPlayAlongHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.file_open),
                label: Text(l.midiPlayAlongChoose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
