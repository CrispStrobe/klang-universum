// lib/features/games/composition/loop_mixer_screen.dart
//
// "Loop-Mixer" — a kid loop-mixer toy. Five cards (drums · bass · chords ·
// melody · sparkle) each toggle a pre-authored 2-bar loop on/off; everything
// is in C pentatonic so any combination grooves (the Colour Melody rule). A
// creative sandbox: no stars, no wrong answers.
//
// Audio: LoopEngine mixes the enabled tracks offline into ONE looping WAV
// (sample-accurate sync for free) played on a dedicated LoopPlayerService.
// The screen owns the musical clock (a Stopwatch); on every toggle the fresh
// mix starts at the clock's phase (`play(position: …)`), so layers drop in
// and out without the bar ever restarting. A Ticker (created in initState —
// never a lazy `late final`, see CLAUDE.md) drives the step playhead.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:klang_universum/core/audio/loop_engine.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/loop_player_service.dart';
import 'package:klang_universum/features/games/widgets/game_app_bar.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

class LoopMixerScreen extends StatefulWidget {
  const LoopMixerScreen({super.key});

  /// The tempo presets (all keep the step grid integral — see LoopTiming).
  static const tempos = [75, 100, 120];

  @override
  State<LoopMixerScreen> createState() => _LoopMixerScreenState();
}

/// Test handle onto the running game (the state class is private).
@visibleForTesting
abstract interface class LoopMixerTester {
  Set<String> get enabledTracks;
  bool get isPlaying;
  int get tempoBpm;
  void toggleTrack(String id);
  void setTempo(int bpm);
  void stopAll();
}

class _LoopMixerScreenState extends State<LoopMixerScreen>
    with SingleTickerProviderStateMixin
    implements LoopMixerTester {
  final _engine = LoopEngine();
  final _loop = LoopPlayerService();

  /// The groove's musical clock: playback phase is derived from it, never
  /// from the player, so toggles can re-enter the loop in phase.
  final _clock = Stopwatch();

  late final Ticker _ticker;
  final _step = ValueNotifier<int>(-1);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final t = _engine.timing;
      _step.value = _clock.isRunning
          ? (_clock.elapsedMilliseconds % t.totalMs) ~/ t.stepMs
          : -1;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _step.dispose();
    _loop.dispose();
    super.dispose();
  }

  // --- LoopMixerTester ---
  @override
  Set<String> get enabledTracks => Set.unmodifiable(_engine.enabled);
  @override
  bool get isPlaying => _clock.isRunning;
  @override
  int get tempoBpm => _engine.tempoBpm;
  @override
  void toggleTrack(String id) => _toggle(id);
  @override
  void setTempo(int bpm) => _setTempo(bpm);
  @override
  void stopAll() => _stopAll();

  void _toggle(String id) {
    setState(() => _engine.toggle(id));
    _syncPlayback();
  }

  void _setTempo(int bpm) {
    if (bpm == _engine.tempoBpm) return;
    setState(() => _engine.tempoBpm = bpm);
    // A new tempo means a new grid — restart the groove from the top.
    _clock
      ..stop()
      ..reset();
    _syncPlayback();
  }

  void _stopAll() {
    setState(_engine.enabled.clear);
    _syncPlayback();
  }

  /// Restarts/stops/swaps the looping mix to match the enabled set, keeping
  /// the musical phase: the new mix starts exactly where the clock says the
  /// groove is, so the beat never resets when a card toggles.
  void _syncPlayback() {
    if (_engine.enabled.isEmpty) {
      _clock
        ..stop()
        ..reset();
      _loop.stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return; // master mute
    final wav = _engine.renderLoop();
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
    }
    final position = Duration(
      milliseconds: _clock.elapsedMilliseconds % _engine.timing.totalMs,
    );
    _loop.playLoop(wav, position: position);
  }

  static const _trackIcons = <String, IconData>{
    'drums': Icons.album,
    'bass': Icons.speaker,
    'chords': Icons.piano,
    'melody': Icons.music_note,
    'sparkle': Icons.auto_awesome,
  };

  // One stable colour per card (the drums are unpitched, so a warm brown
  // instead of a pitch-class colour).
  static const _trackColors = <String, Color>{
    'drums': Color(0xFF795548),
    'bass': Color(0xFFE53935), // C red — the bass grounds the key
    'chords': Color(0xFF00ACC1), // G cyan
    'melody': Color(0xFFF9A825), // E amber
    'sparkle': Color(0xFF3949AB), // A indigo
  };

  String _trackLabel(AppLocalizations l10n, String id) => switch (id) {
        'drums' => l10n.loopMixerTrackDrums,
        'bass' => l10n.loopMixerTrackBass,
        'chords' => l10n.loopMixerTrackChords,
        'melody' => l10n.loopMixerTrackMelody,
        _ => l10n.loopMixerTrackSparkle,
      };

  String _tempoLabel(AppLocalizations l10n, int bpm) => switch (bpm) {
        75 => l10n.loopMixerTempoChill,
        120 => l10n.loopMixerTempoFast,
        _ => l10n.loopMixerTempoGroove,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: GameAppBar(title: l10n.gameLoopMixer),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                l10n.loopMixerPrompt,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              _Playhead(step: _step),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  children: [
                    for (final track in _engine.tracks)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _TrackCard(
                            color: _trackColors[track.id]!,
                            icon: _trackIcons[track.id]!,
                            label: _trackLabel(l10n, track.id),
                            active: _engine.enabled.contains(track.id),
                            onTap: () => _toggle(track.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final bpm in LoopMixerScreen.tempos)
                          ChoiceChip(
                            label: Text(_tempoLabel(l10n, bpm)),
                            selected: _engine.tempoBpm == bpm,
                            onSelected: (_) => _setTempo(bpm),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _engine.enabled.isEmpty ? null : _stopAll,
                    icon: const Icon(Icons.stop),
                    label: Text(l10n.loopMixerStop),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of step dots (2 bars × 8 eighths) with the sounding step lit. Only
/// this leaf listens to the ticker's step notifier, so the per-frame update
/// never rebuilds the cards.
class _Playhead extends StatelessWidget {
  const _Playhead({required this.step});

  final ValueListenable<int> step;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<int>(
      valueListenable: step,
      builder: (context, current, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < LoopTiming.totalSteps; i++)
            Container(
              width: 12,
              height: 12,
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : (i % 4 == 0 ? 10 : 4),
              ),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current
                    ? base
                    : base.withValues(alpha: i.isEven ? 0.25 : 0.12),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.4),
            width: active ? 3 : 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: 30),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 12),
            Icon(
              active ? Icons.volume_up : Icons.volume_off,
              color: foreground.withValues(alpha: 0.7),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
