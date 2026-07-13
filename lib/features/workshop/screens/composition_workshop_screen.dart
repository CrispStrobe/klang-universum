// lib/features/workshop/screens/composition_workshop_screen.dart
//
// "Kompositions-Werkstatt" / "Composition Workshop" — the score editor that
// grows toward professional score-writing depth (see docs/WORKSHOP_PLAN.md).
// It is intentionally simple by default: pick a note value (and, when wanted, a
// dot or an accidental), tap the staff to write, tap a note to select it and
// re-pitch or delete it. Under the hood everything runs through [ScoreDocument]
// — an editable model with multi-level undo/redo — so new notation features
// slot in without the screen assembling a Score by hand.
//
// Compared with the "My Melody" sandbox this adds bar-lines per time signature,
// rests, dotted rhythms, sharps/flats, and real undo/redo, and saves to the
// Song Book as MusicXML / exports ABC.

// Material's Stepper also exports a `Step`; partitura's pitch Step wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/music_glyph.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

/// A choosable note value: glyph + base duration.
typedef _Value = ({String glyph, DurationBase base});

const _values = <_Value>[
  (glyph: Smufl.wholeNote, base: DurationBase.whole),
  (glyph: Smufl.halfNote, base: DurationBase.half),
  (glyph: Smufl.quarterNote, base: DurationBase.quarter),
  (glyph: Smufl.eighthNote, base: DurationBase.eighth),
  (glyph: Smufl.sixteenthNote, base: DurationBase.sixteenth),
];

/// The accidental the next placed / re-pitched note gets.
enum _Accidental { natural, sharp, flat }

int _alterOf(_Accidental a) => switch (a) {
      _Accidental.natural => 0,
      _Accidental.sharp => 1,
      _Accidental.flat => -1,
    };

class CompositionWorkshopScreen extends StatefulWidget {
  const CompositionWorkshopScreen({super.key});

  static const maxNotes = 64;

  @override
  State<CompositionWorkshopScreen> createState() =>
      _CompositionWorkshopScreenState();
}

/// Typed window into the editor for widget tests.
@visibleForTesting
abstract interface class CompositionWorkshopTester {
  int get noteCount;
  int get barCount;
}

class _CompositionWorkshopScreenState extends State<CompositionWorkshopScreen>
    implements CompositionWorkshopTester {
  final ScoreDocument _doc = ScoreDocument();

  DurationBase _pendingBase = DurationBase.quarter;
  bool _dotted = false;
  _Accidental _accidental = _Accidental.natural;

  @override
  int get noteCount => _doc.length;

  @override
  int get barCount => _doc.barCount;

  NoteDuration get _pendingDuration =>
      NoteDuration(_pendingBase, dots: _dotted ? 1 : 0);

  void _onStaffTap(StaffTarget target) {
    final pitch =
        target.pitchFor(_doc.clef, preferredAlter: _alterOf(_accidental));
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 400);
    setState(() {
      final selected = _doc.selected;
      if (selected != null && !selected.isRest) {
        _doc.repitchSelected(pitch);
        _doc.clearSelection();
      } else if (_doc.length < CompositionWorkshopScreen.maxNotes) {
        _doc.insertNote(pitch, _pendingDuration);
      }
    });
  }

  void _onElementTap(String id) => setState(() => _doc.toggleSelected(id));

  void _addRest() {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    setState(() => _doc.insertRest(_pendingDuration));
  }

  void _play() {
    if (_doc.isEmpty) return;
    context.read<AudioService>().playSequence([
      for (final e in _doc.elements)
        if (!e.isRest)
          (
            e.pitch!.midiNumber,
            (e.duration.toFraction().toDouble() * 4 * 480).round(),
          ),
    ]);
  }

  // Export the score as ABC notation — a compact text form that pastes into ABC
  // tools and back into the Song Book importer.
  Future<void> _exportAbc() async {
    if (_doc.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final abc = scoreToAbc(_doc.buildScore());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workshopExportAbc),
        content: SingleChildScrollView(child: SelectableText(abc)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: abc));
              Navigator.of(ctx).pop();
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.workshopCopied)),
              );
            },
            icon: const Icon(Icons.copy),
            label: Text(l10n.workshopCopy),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_doc.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final songs = context.read<UserSongsService>();

    final controller = TextEditingController(text: l10n.myMelodyDefaultName);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.myMelodySaveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.myMelodySave),
          ),
        ],
      ),
    );
    if (title == null) return;
    final name = title.trim().isEmpty ? l10n.myMelodyDefaultName : title.trim();
    songs.addSong(
      ImportedSong(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: name,
        musicXml: scoreToMusicXml(_doc.buildScore()),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.myMelodySaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedId = _doc.selectedId;
    final theme = PartituraTheme.kids.copyWith(
      elementColors: {if (selectedId != null) selectedId: Colors.amber},
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workshopComposeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.abc),
            tooltip: l10n.workshopExportAbc,
            onPressed: _doc.isEmpty ? null : _exportAbc,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _TimeSignaturePicker(
                value: _doc.timeSignature,
                label: l10n.workshopTimeSignature,
                onChanged: (t) => setState(() => _doc.setTimeSignature(t)),
              ),
              const SizedBox(height: 8),
              // Note value.
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final v in _values)
                    ChoiceChip(
                      avatar: MusicGlyph(v.glyph, size: 22),
                      label: Text(_beatsLabel(l10n, v.base)),
                      selected: _pendingBase == v.base,
                      onSelected: (_) => setState(() => _pendingBase = v.base),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Dot + accidental modifiers.
              Wrap(
                spacing: 12,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    avatar: const Text('.', style: TextStyle(fontSize: 20)),
                    label: Text(l10n.workshopDot),
                    selected: _dotted,
                    onSelected: (v) => setState(() => _dotted = v),
                  ),
                  SegmentedButton<_Accidental>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _Accidental.natural,
                        label: Text('♮'),
                      ),
                      ButtonSegment(value: _Accidental.sharp, label: Text('♯')),
                      ButtonSegment(value: _Accidental.flat, label: Text('♭')),
                    ],
                    selected: {_accidental},
                    onSelectionChanged: (s) =>
                        setState(() => _accidental = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: InteractiveStaff(
                        score: _doc.buildScore(),
                        theme: theme,
                        staffSpace: 14,
                        onStaffTap: _onStaffTap,
                        onElementTap: _onElementTap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                selectedId == null ? l10n.workshopHint : l10n.workshopEditHint,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              _Toolbar(
                canPlay: !_doc.isEmpty,
                canSave: !_doc.isEmpty,
                canDelete: _doc.selectedId != null,
                canUndo: _doc.canUndo,
                canRedo: _doc.canRedo,
                canClear: !_doc.isEmpty,
                onPlay: _play,
                onSave: _save,
                onRest: _addRest,
                onDelete: () => setState(_doc.deleteSelected),
                onUndo: () => setState(_doc.undo),
                onRedo: () => setState(_doc.redo),
                onClear: () => setState(_doc.clearAll),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _beatsLabel(AppLocalizations l10n, DurationBase base) {
    // Quarter-note beats this value lasts (in a /4 metre).
    final beats = NoteDuration(base).toFraction().toDouble() * 4;
    if (beats == 0.25) return l10n.quarterBeat;
    if (beats == 0.5) return l10n.halfBeat;
    return l10n.beatsCount(beats.toInt());
  }
}

/// The 2/4 · 3/4 · 4/4 chooser (with its inline label).
class _TimeSignaturePicker extends StatelessWidget {
  const _TimeSignaturePicker({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final TimeSignature value;
  final String label;
  final ValueChanged<TimeSignature> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 8),
        SegmentedButton<TimeSignature>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TimeSignature.twoFour, label: Text('2/4')),
            ButtonSegment(value: TimeSignature.threeFour, label: Text('3/4')),
            ButtonSegment(value: TimeSignature.fourFour, label: Text('4/4')),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ],
    );
  }
}

/// The action row under the staff.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.canPlay,
    required this.canSave,
    required this.canDelete,
    required this.canUndo,
    required this.canRedo,
    required this.canClear,
    required this.onPlay,
    required this.onSave,
    required this.onRest,
    required this.onDelete,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
  });

  final bool canPlay, canSave, canDelete, canUndo, canRedo, canClear;
  final VoidCallback onPlay, onSave, onRest, onDelete, onUndo, onRedo, onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        FilledButton.icon(
          onPressed: canPlay ? onPlay : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.myMelodyPlay),
        ),
        FilledButton.tonalIcon(
          onPressed: canSave ? onSave : null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(l10n.myMelodySave),
        ),
        FilledButton.tonalIcon(
          onPressed: onRest,
          icon: const Icon(Icons.music_off_outlined),
          label: Text(l10n.workshopRest),
        ),
        FilledButton.tonalIcon(
          onPressed: canDelete ? onDelete : null,
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.workshopDelete),
        ),
        IconButton.filledTonal(
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(Icons.undo),
          tooltip: l10n.myMelodyUndo,
        ),
        IconButton.filledTonal(
          onPressed: canRedo ? onRedo : null,
          icon: const Icon(Icons.redo),
          tooltip: l10n.workshopRedo,
        ),
        TextButton.icon(
          onPressed: canClear ? onClear : null,
          icon: const Icon(Icons.delete_sweep_outlined),
          label: Text(l10n.myMelodyClear),
        ),
      ],
    );
  }
}
