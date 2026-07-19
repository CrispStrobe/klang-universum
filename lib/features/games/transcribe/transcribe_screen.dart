// N2 — "Transcribe a recording". Pick an audio file (or record from the mic),
// run the auto-router pipeline (monophonic pure-Dart, or neural Basic Pitch when
// its model is present on native), and open the result as a real score in the
// Song Book — playable, editable, saveable.
//
// The heavy DSP runs on the UI isolate for now (recordings are short); a future
// pass can move it to a compute() isolate. Test seams (`debugPickAudio`,
// `debugNeural`) let a widget test drive the flow with no file-picker/mic/ONNX.

import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:comet_beat/core/audio/transcription/transcription_service.dart';
import 'package:comet_beat/features/games/songs/song_screen.dart';
import 'package:comet_beat/features/games/transcribe/neural_provider.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:crisp_notation_core/crisp_notation_core.dart' show Score;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How the user wants the engine chosen.
enum EngineChoice { auto, monophonic, neural }

class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({super.key, this.debugPickAudio, this.debugNeural});

  /// Test seam: replaces the file-picker. Returns WAV bytes, or null to cancel.
  final Future<Uint8List?> Function()? debugPickAudio;

  /// Test seam: replaces neural-engine loading.
  final Future<NeuralTranscriber?> Function({bool download})? debugNeural;

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  bool _busy = false;
  String? _error;
  EngineChoice _choice = EngineChoice.auto;
  TranscriptionResult? _result;

  Future<Uint8List?> _pickAudio() async {
    if (widget.debugPickAudio != null) return widget.debugPickAudio!();
    const group = XTypeGroup(label: 'Audio', extensions: ['wav']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<NeuralTranscriber?> _neural({bool download = false}) {
    final loader = widget.debugNeural ?? loadNeuralTranscriber;
    return loader(download: download);
  }

  Future<void> _transcribe() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final bytes = await _pickAudio();
      if (bytes == null) {
        setState(() => _busy = false); // cancelled
        return;
      }
      // Neural only when the user allows it and (native) the model is present.
      final neural = _choice == EngineChoice.monophonic
          ? null
          : await _neural(download: _choice == EngineChoice.neural);
      final force = switch (_choice) {
        EngineChoice.monophonic => TranscriptionEngine.monophonic,
        EngineChoice.neural => TranscriptionEngine.neural,
        EngineChoice.auto => null,
      };
      final result = await transcribeRecording(
        bytes,
        neural: neural,
        forceEngine: force,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _openInSongBook(Score score, AppLocalizations l10n) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongScreen.fromScore(
          title: l10n.transcribeTitle,
          score: score,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.transcribeTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.transcribeIntro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SegmentedButton<EngineChoice>(
              segments: [
                ButtonSegment(
                  value: EngineChoice.auto,
                  label: Text(l10n.transcribeEngineAuto),
                ),
                ButtonSegment(
                  value: EngineChoice.monophonic,
                  label: Text(l10n.transcribeEngineMono),
                ),
                ButtonSegment(
                  value: EngineChoice.neural,
                  label: Text(l10n.transcribeEngineNeural),
                ),
              ],
              selected: {_choice},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _choice = s.first),
            ),
            if (_choice == EngineChoice.neural && kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.transcribeNeuralWebNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _transcribe,
              icon: const Icon(Icons.audio_file),
              label: Text(l10n.transcribePickFile),
            ),
            const SizedBox(height: 24),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(
                l10n.transcribeError(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_result != null)
              Expanded(child: _resultCard(_result!, l10n)),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(TranscriptionResult r, AppLocalizations l10n) {
    final engineName = r.engine == TranscriptionEngine.neural
        ? l10n.transcribeEngineNeural
        : l10n.transcribeEngineMono;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.transcribeResult(r.notes.length, r.bpm.round()),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.transcribeEngineUsed(engineName)),
            const SizedBox(height: 16),
            if (r.notes.isEmpty)
              Text(l10n.transcribeNoNotes)
            else
              FilledButton.tonalIcon(
                onPressed: () => _openInSongBook(r.score, l10n),
                icon: const Icon(Icons.menu_book),
                label: Text(l10n.transcribeOpenSongBook),
              ),
          ],
        ),
      ),
    );
  }
}
