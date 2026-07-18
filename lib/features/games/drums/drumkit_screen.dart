// lib/features/games/drums/drumkit_screen.dart
//
// "Drumkit / BoomBox" — a GarageBand-style virtual drum kit + a step beat-grid,
// a fifth Workshop mode. Tap the pads to audition a drum; toggle the grid to
// build a loop; hit Play to hear it. The pattern IS a `DrumRowsPattern` — the
// SAME model the Loop Mixer's beat track and the Tracker's percussion channel
// use — so it's the shared beat editor (interconnection to those is a follow-up).

import 'dart:typed_data';

import 'package:comet_beat/core/audio/loop_engine.dart'
    show DrumRowsPattern, LoopTiming, kPatternSteps;
import 'package:comet_beat/core/audio/synth.dart'
    show Drum, renderDrum, wavBytes;
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/core/services/gapless_loop_player.dart';
import 'package:comet_beat/features/games/widgets/game_app_bar.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

/// Test handle onto the running kit (the state class is private).
@visibleForTesting
abstract interface class DrumkitTester {
  int get steps;
  bool cellAt(Drum drum, int step);
  void toggle(Drum drum, int step);
  int get hitCount;
  bool get isPlaying;
  void togglePlay();
  void stop();
  void clear();
  void tapPad(Drum drum);
  int get tempo;
  void setTempo(int bpm);
}

class DrumkitScreen extends StatefulWidget {
  const DrumkitScreen({super.key});

  static const tempos = [80, 100, 120, 140];

  @override
  State<DrumkitScreen> createState() => _DrumkitScreenState();
}

class _DrumkitScreenState extends State<DrumkitScreen>
    with SingleTickerProviderStateMixin
    implements DrumkitTester {
  // One boolean row per drum voice; each row is kPatternSteps (16 = 2 bars).
  final Map<Drum, List<bool>> _rows = {
    for (final d in Drum.values) d: List<bool>.filled(kPatternSteps, false),
  };

  final _loop = GaplessLoopPlayer();
  final _clock = Stopwatch();
  late final Ticker _ticker;
  final _step = ValueNotifier<int>(-1);
  int _tempo = 100;

  LoopTiming get _timing => LoopTiming(tempoBpm: _tempo); // 2 bars (default)

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!_clock.isRunning) {
        _step.value = -1;
        return;
      }
      final t = _timing;
      _step.value = (_clock.elapsedMilliseconds % t.totalMs) ~/ t.stepMs;
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

  // --- Audio -----------------------------------------------------------------

  Int16List _toPcm16(Float64List pcm) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = (pcm[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return out;
  }

  Uint8List _renderWav() =>
      wavBytes(_toPcm16(DrumRowsPattern(_rows).render(_timing)));

  /// Re-render + re-swap the loop IN PHASE after an edit (so the beat doesn't
  /// restart) — the same trick the Loop Mixer / Tracker use.
  void _syncPlayback() {
    if (!_clock.isRunning) return;
    if (!context.read<AudioService>().soundOn) return;
    final pos =
        Duration(milliseconds: _clock.elapsedMilliseconds % _timing.totalMs);
    _loop.playLoop(_renderWav(), position: pos);
  }

  // --- DrumkitTester ---------------------------------------------------------

  @override
  int get steps => kPatternSteps;

  @override
  bool cellAt(Drum drum, int step) => _rows[drum]![step];

  @override
  void toggle(Drum drum, int step) {
    setState(() => _rows[drum]![step] = !_rows[drum]![step]);
    _syncPlayback();
  }

  @override
  int get hitCount =>
      _rows.values.fold(0, (n, row) => n + row.where((b) => b).length);

  @override
  bool get isPlaying => _clock.isRunning;

  @override
  void togglePlay() {
    if (_clock.isRunning) {
      stop();
      return;
    }
    if (!context.read<AudioService>().soundOn) return;
    _clock
      ..reset()
      ..start();
    _loop.playLoop(_renderWav());
    setState(() {});
  }

  @override
  void stop() {
    _clock
      ..stop()
      ..reset();
    _loop.stop();
    _step.value = -1;
    setState(() {});
  }

  @override
  void clear() {
    setState(() {
      for (final row in _rows.values) {
        row.fillRange(0, row.length, false);
      }
    });
    _syncPlayback();
  }

  @override
  void tapPad(Drum drum) {
    context
        .read<AudioService>()
        .playWavBytes(wavBytes(_toPcm16(renderDrum(drum))));
  }

  @override
  int get tempo => _tempo;

  @override
  void setTempo(int bpm) {
    setState(() => _tempo = bpm);
    _syncPlayback();
  }

  // --- UI --------------------------------------------------------------------

  String _drumLabel(AppLocalizations l10n, Drum d) => switch (d) {
        Drum.kick => l10n.drumkitKick,
        Drum.snare => l10n.drumkitSnare,
        Drum.hat => l10n.drumkitHat,
      };

  IconData _drumIcon(Drum d) => switch (d) {
        Drum.kick => Icons.circle,
        Drum.snare => Icons.blur_circular,
        Drum.hat => Icons.brightness_high,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GameAppBar(title: l10n.drumkitTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The step grid: one row per drum, kPatternSteps toggles.
              Expanded(
                child: Column(
                  children: [
                    for (final drum in Drum.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(
                                  _drumLabel(l10n, drum),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              for (var s = 0; s < kPatternSteps; s++)
                                Expanded(
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: _step,
                                    builder: (context, playing, _) {
                                      final on = _rows[drum]![s];
                                      final beat = s % 2 == 0;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: GestureDetector(
                                          onTap: () => toggle(drum, s),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: on
                                                  ? scheme.primary
                                                  : (beat
                                                      ? scheme
                                                          .surfaceContainerHighest
                                                      : scheme
                                                          .surfaceContainerLow),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: playing == s
                                                  ? Border.all(
                                                      color: scheme.tertiary,
                                                      width: 2,
                                                    )
                                                  : null,
                                            ),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // The pads — tap to audition a drum.
              Row(
                children: [
                  for (final drum in Drum.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilledButton.tonalIcon(
                          onPressed: () => tapPad(drum),
                          icon: Icon(_drumIcon(drum)),
                          label: Text(_drumLabel(l10n, drum)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Transport + tempo + clear.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: togglePlay,
                    icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(isPlaying ? l10n.songStop : l10n.myMelodyPlay),
                  ),
                  for (final bpm in DrumkitScreen.tempos)
                    ChoiceChip(
                      label: Text('$bpm'),
                      selected: _tempo == bpm,
                      onSelected: (_) => setTempo(bpm),
                    ),
                  OutlinedButton.icon(
                    onPressed: hitCount == 0 ? null : clear,
                    icon: const Icon(Icons.clear),
                    label: Text(l10n.trackerClear),
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
