// "Load SoundFont" — a modal sheet that opens a `.sf2`/`.sf3` SoundFont, lists
// its General-MIDI presets, auditions the selected one, and returns the chosen
// preset as a ready [TrackerInstrument]. A screen wires it in one line:
//
//   final inst = await showSoundFontSheet(context);
//   if (inst != null) song.instruments.add(inst);  // drop into the pool
//
// All the load / browse / audition logic is self-contained here (mirroring
// libraries-and-tab's `showSampleLibrarySheet`), over the headless
// `soundfont_loader` facade — no engine/model/screen files are touched. Strings
// are literal English pending localization at wire-in.

import 'dart:typed_data';

import 'package:comet_beat/core/audio/sf2/sf2.dart'
    show Sf2Preset, VorbisDecode;
import 'package:comet_beat/core/audio/sf2/soundfont_loader.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';
import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _kSoundFontGroup = XTypeGroup(
  label: 'SoundFonts',
  extensions: ['sf2', 'sf3'],
);

/// A picked SoundFont file: its raw [bytes] and a display [name].
typedef PickedSoundFont = ({Uint8List bytes, String name});

/// File-picker seam so the sheet is testable without a real file dialog.
typedef SoundFontPicker = Future<PickedSoundFont?> Function();

Future<PickedSoundFont?> _defaultPick() async {
  final file = await openFile(acceptedTypeGroups: const [_kSoundFontGroup]);
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), name: file.name);
}

/// Shows the "Load SoundFont" browser. Returns the chosen preset as a ready
/// [TrackerInstrument], or null if the user cancels. [pick] and [vorbis] are
/// injectable for tests; audition plays through the ambient [AudioService] when
/// one is provided (a no-op otherwise).
Future<TrackerInstrument?> showSoundFontSheet(
  BuildContext context, {
  SoundFontPicker pick = _defaultPick,
  VorbisDecode? vorbis,
}) {
  return showModalBottomSheet<TrackerInstrument>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SoundFontSheet(pick: pick, vorbis: vorbis),
  );
}

class _SoundFontSheet extends StatefulWidget {
  const _SoundFontSheet({required this.pick, this.vorbis});

  final SoundFontPicker pick;
  final VorbisDecode? vorbis;

  @override
  State<_SoundFontSheet> createState() => _SoundFontSheetState();
}

class _SoundFontSheetState extends State<_SoundFontSheet> {
  LoadedSoundFont? _font;
  String? _fontName;
  Sf2Preset? _selected;
  TrackerInstrument? _selectedInst;
  String? _error;
  bool _busy = false;
  String _filter = '';

  Future<void> _choose() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await widget.pick();
      if (picked == null) {
        setState(() => _busy = false);
        return;
      }
      final loaded = loadSoundFont(picked.bytes, vorbis: widget.vorbis);
      setState(() {
        _font = loaded;
        _fontName = picked.name;
        _selected = null;
        _selectedInst = null;
        _filter = '';
        _busy = false;
      });
    } on SoundFontLoadException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this SoundFont.';
        _busy = false;
      });
    }
  }

  void _select(Sf2Preset p) {
    final font = _font;
    if (font == null) return;
    final inst = soundFontInstrument(font, p);
    setState(() {
      _selected = p;
      _selectedInst = inst;
    });
    _audition(inst);
  }

  /// Play a short middle-C preview of [inst] through the AudioService, if one is
  /// available (guarded so the sheet works in tests without a provider).
  void _audition(TrackerInstrument inst) {
    try {
      final audio = context.read<AudioService>();
      const timing = TrackerTiming(rows: 4, stepsPerBeat: 2);
      final cells = [
        const TrackerCell(midi: 60),
        ...List<TrackerCell>.filled(3, TrackerCell.empty),
      ];
      audio.playWavBytes(pcmFloatToWav(inst.renderChannel(cells, timing)));
    } catch (_) {
      // No AudioService in scope (e.g. tests) → skip the preview silently.
    }
  }

  List<Sf2Preset> get _visiblePresets {
    final all = _font?.presets ?? const <Sf2Preset>[];
    if (_filter.trim().isEmpty) return all;
    final q = _filter.trim().toLowerCase();
    return all
        .where((p) => soundFontPresetLabel(p).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final font = _font;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme),
            const Divider(height: 1),
            if (font == null)
              Expanded(child: _empty(theme))
            else
              Expanded(child: _browser(theme, font)),
            const Divider(height: 1),
            _footer(theme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.piano),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Load SoundFont', style: theme.textTheme.titleMedium),
                  if (_fontName != null)
                    Text(
                      _fontName!,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (_font != null)
              Chip(
                label: Text(
                  '${_font!.presets.length} sounds'
                  '${_font!.compressed ? ' · .sf3' : ''}',
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      );

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Open a .sf2 or .sf3 SoundFont to browse its instruments.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose SoundFont file…'),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _browser(ThemeData theme, LoadedSoundFont font) {
    final presets = _visiblePresets;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search instruments',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: presets.length,
            itemBuilder: (_, i) {
              final p = presets[i];
              final selected = identical(p, _selected);
              return ListTile(
                dense: true,
                selected: selected,
                leading: Icon(
                  p.bank == 128 ? Icons.music_note : Icons.queue_music,
                ),
                title: Text(soundFontPresetLabel(p)),
                trailing: selected
                    ? const Icon(Icons.play_arrow)
                    : const Icon(Icons.volume_up, size: 18),
                onTap: () => _select(p),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _footer(ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (_font != null)
              TextButton.icon(
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Change file'),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _selectedInst == null
                  ? null
                  : () => Navigator.of(context).pop(_selectedInst),
              child: const Text('Use this sound'),
            ),
          ],
        ),
      );
}
