// The "Instrument sound" voice picker — a searchable, category-filtered browser
// over the whole sample-free procedural palette (the same voices the Tracker /
// Sound Library offer: Tonal additive + FM + subtractive, Chiptune sfxr, Plucked
// Karplus). Tap a voice to hear it; long-press (or the check) to choose it as the
// app's global playback voice. Returns the chosen voiceId, or null if cancelled.
//
// Library + catalog (sampled) voices are a follow-up — this ships the built-in
// procedural palette, which is what "Tonal / Chiptune / …" refers to.

import 'package:comet_beat/core/audio/synth.dart' show Instrument;
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart'
    show pcmFloatToWav;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens the voice picker. [currentId] marks the current selection.
Future<String?> showVoicePicker(BuildContext context, {String? currentId}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => VoicePickerSheet(currentId: currentId),
  );
}

/// A display label for a built-in voice id (l10n where named, else humanized).
String voiceLabel(AppLocalizations l10n, String id) => switch (id) {
      'piano' => l10n.instrumentPiano,
      'cello' => l10n.instrumentCello,
      'flute' => l10n.instrumentFlute,
      'musicBox' => l10n.instrumentMusicBox,
      'zap' => l10n.trackerSfxrZap,
      'blip' => l10n.trackerSfxrBlip,
      'laser' => l10n.trackerSfxrLaser,
      'coin' => l10n.trackerSfxrCoin,
      'bell' => l10n.trackerSfxrBell,
      'explosion' => l10n.trackerSfxrExplosion,
      _ => _humanize(id),
    };

String _humanize(String id) {
  final spaced = id.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  return spaced.isEmpty ? id : spaced[0].toUpperCase() + spaced.substring(1);
}

IconData _categoryIcon(SoundCategory c) => switch (c) {
      SoundCategory.tonal => Icons.piano,
      SoundCategory.plucked => Icons.music_note,
      SoundCategory.chiptune => Icons.videogame_asset,
      SoundCategory.drum => Icons.album,
      SoundCategory.recorded => Icons.graphic_eq,
    };

String _categoryLabel(AppLocalizations l10n, SoundCategory c) => switch (c) {
      SoundCategory.tonal => l10n.voiceCatTonal,
      SoundCategory.plucked => l10n.voiceCatPlucked,
      SoundCategory.chiptune => l10n.voiceCatChiptune,
      SoundCategory.drum => l10n.soundLibraryCatDrums,
      SoundCategory.recorded => l10n.soundLibraryCatSamples,
    };

@visibleForTesting
class VoicePickerSheet extends StatefulWidget {
  const VoicePickerSheet({this.currentId, super.key});
  final String? currentId;

  @override
  State<VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<VoicePickerSheet> {
  final _search = TextEditingController();
  SoundCategory? _filter; // null = All

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The categories actually present in the palette, in a stable order.
  List<SoundCategory> get _categories {
    const order = [
      SoundCategory.tonal,
      SoundCategory.chiptune,
      SoundCategory.plucked,
      SoundCategory.drum,
      SoundCategory.recorded,
    ];
    final present = kTrackerInstruments.map((o) => o.category).toSet();
    return [
      for (final c in order)
        if (present.contains(c)) c,
    ];
  }

  List<InstrumentOption> get _visible {
    final q = _search.text.trim().toLowerCase();
    final l10n = AppLocalizations.of(context)!;
    return [
      for (final o in kTrackerInstruments)
        if ((_filter == null || o.category == _filter) &&
            (q.isEmpty || voiceLabel(l10n, o.id).toLowerCase().contains(q)))
          o,
    ];
  }

  void _preview(InstrumentOption o) {
    final inst = o.build();
    final pcm = inst.renderChannel(
      [const TrackerCell(midi: 67)],
      const TrackerTiming(rows: 6),
    );
    if (pcm.isEmpty) return;
    context.read<AudioService>().playWavBytes(pcmFloatToWav(pcm));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visible = _visible;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.voicePickerTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.voiceSearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(l10n.voiceCatAll),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                  ),
                  for (final c in _categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_categoryLabel(l10n, c)),
                        selected: _filter == c,
                        onSelected: (_) => setState(() => _filter = c),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.voicePreview,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 320,
              child: visible.isEmpty
                  ? Center(child: Text(l10n.libraryNoResults))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final o = visible[i];
                        final selected = o.id == widget.currentId;
                        return ListTile(
                          dense: true,
                          leading: Icon(_categoryIcon(o.category)),
                          title: Text(voiceLabel(l10n, o.id)),
                          trailing: selected
                              ? const Icon(Icons.check, size: 20)
                              : null,
                          selected: selected,
                          onTap: () => _preview(o), // hear it
                          onLongPress: () =>
                              Navigator.of(context).pop(o.id), // choose it
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether [id] is one of the four classic additive voices.
bool isAdditiveVoice(String id) => Instrument.values.any((e) => e.name == id);
