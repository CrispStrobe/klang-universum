// lib/features/workshop/screens/composition_workshop_screen.dart
//
// "Kompositions-Werkstatt" / "Composition Workshop" — a touch-first score
// editor (see docs/WORKSHOP_PLAN.md). The layout: a full-bleed, zoomable score
// canvas on top, and a bottom input dock — a duration/accidental glyph strip
// above a swappable pitch surface (on-screen piano or tap-the-staff). Entry is
// "pick a value, then a pitch". A status line always shows the armed value and
// the current selection, so there is never a hidden mode. Everything runs
// through [ScoreDocument] (editable model + multi-level undo/redo).

// Material's Stepper also exports a `Step`; partitura's pitch Step wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/note_reading/note_names.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/workshop/model/score_document.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/midi_pitch.dart';
import 'package:klang_universum/shared/widgets/music_glyph.dart';
import 'package:klang_universum/shared/widgets/piano_keyboard.dart';
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

/// Where pitches are entered from.
enum _PitchSurface { piano, staff }

/// The accidental the next placed note gets (or the selected note is set to).
enum _Accidental { natural, sharp, flat }

int _alterOf(_Accidental a) => switch (a) {
      _Accidental.natural => 0,
      _Accidental.sharp => 1,
      _Accidental.flat => -1,
    };

_Accidental _accidentalOf(int alter) => alter > 0
    ? _Accidental.sharp
    : alter < 0
        ? _Accidental.flat
        : _Accidental.natural;

const _accidentalGlyph = {
  _Accidental.natural: '♮',
  _Accidental.sharp: '♯',
  _Accidental.flat: '♭',
};

/// Key-signature choices offered in the settings sheet (circle-of-fifths).
const _keyChoices = [-4, -3, -2, -1, 0, 1, 2, 3, 4];

String _keyLabel(int fifths) =>
    fifths == 0 ? '♮' : (fifths > 0 ? '$fifths♯' : '${-fifths}♭');

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
  _PitchSurface _surface = _PitchSurface.piano;

  @override
  int get noteCount => _doc.length;

  @override
  int get barCount => _doc.barCount;

  NoteDuration get _pendingDuration =>
      NoteDuration(_pendingBase, dots: _dotted ? 1 : 0);

  AudioService get _audio => context.read<AudioService>();

  void _syncControlsToSelection() {
    final e = _doc.selected;
    if (e == null) return;
    _pendingBase = e.duration.base;
    _dotted = e.duration.dots > 0;
    _accidental =
        e.isRest ? _Accidental.natural : _accidentalOf(e.pitch!.alter);
  }

  // ---- entry -------------------------------------------------------------

  void _placePitch(Pitch pitch) {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    _audio.playMidiNote(pitch.midiNumber, ms: 400);
    setState(() => _doc.insertNote(pitch, _pendingDuration));
  }

  void _onStaffTap(StaffTarget target) => _placePitch(
        target.pitchFor(_doc.clef, preferredAlter: _alterOf(_accidental)),
      );

  void _onPianoKey(int midi) => _placePitch(pitchFromMidi(midi));

  void _onElementTap(String id) => setState(() {
        _doc.toggleSelected(id);
        _syncControlsToSelection();
      });

  // ---- controls ----------------------------------------------------------

  void _pickValue(DurationBase base) => setState(() {
        _pendingBase = base;
        if (_doc.selected != null) {
          _doc.setDurationOfSelected(NoteDuration(base, dots: _dotted ? 1 : 0));
        }
      });

  void _toggleDot() => setState(() {
        _dotted = !_dotted;
        if (_doc.selected != null) {
          _doc.setDurationOfSelected(
            NoteDuration(_pendingBase, dots: _dotted ? 1 : 0),
          );
        }
      });

  void _pickAccidental(_Accidental a) => setState(() {
        _accidental = a;
        if (_doc.selected != null) _doc.setAccidentalOfSelected(_alterOf(a));
      });

  void _addRest() {
    if (_doc.length >= CompositionWorkshopScreen.maxNotes) return;
    setState(() => _doc.insertRest(_pendingDuration));
  }

  void _selectPrev() => setState(() {
        _doc.selectPrev();
        _syncControlsToSelection();
      });

  void _selectNext() => setState(() {
        _doc.selectNext();
        _syncControlsToSelection();
      });

  void _transpose(int semitones) {
    final before = _doc.selected?.pitch?.midiNumber;
    setState(() {
      _doc.transposeSelected(semitones);
      _syncControlsToSelection();
    });
    final now = _doc.selected?.pitch?.midiNumber;
    if (now != null && now != before) _audio.playMidiNote(now, ms: 300);
  }

  void _play() {
    if (_doc.isEmpty) return;
    _audio.playSequence([
      for (final e in _doc.elements)
        if (!e.isRest)
          (
            e.pitch!.midiNumber,
            (e.duration.toFraction().toDouble() * 4 * 480).round(),
          ),
    ]);
  }

  // ---- sheets / dialogs --------------------------------------------------

  void _openScoreSettings() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.workshopScoreSettings,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l10n.workshopTimeSignature,
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<TimeSignature>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TimeSignature.twoFour,
                          label: Text('2/4'),
                        ),
                        ButtonSegment(
                          value: TimeSignature.threeFour,
                          label: Text('3/4'),
                        ),
                        ButtonSegment(
                          value: TimeSignature.fourFour,
                          label: Text('4/4'),
                        ),
                      ],
                      selected: {_doc.timeSignature},
                      onSelectionChanged: (s) {
                        setState(() => _doc.setTimeSignature(s.first));
                        setSheet(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      l10n.workshopKey,
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: _doc.keySignature.fifths,
                      items: [
                        for (final f in _keyChoices)
                          DropdownMenuItem(value: f, child: Text(_keyLabel(f))),
                      ],
                      onChanged: (f) {
                        setState(
                          () => _doc.setKeySignature(KeySignature(f ?? 0)),
                        );
                        setSheet(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedId = _doc.selectedId;
    final hasSelection = selectedId != null;
    final theme = PartituraTheme.kids.copyWith(
      elementColors: {if (hasSelection) selectedId: Colors.amber},
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workshopComposeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.myMelodyUndo,
            onPressed: _doc.canUndo ? () => setState(_doc.undo) : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.workshopRedo,
            onPressed: _doc.canRedo ? () => setState(_doc.redo) : null,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: l10n.myMelodyPlay,
            onPressed: _doc.isEmpty ? null : _play,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.workshopScoreSettings,
            onPressed: _openScoreSettings,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'save':
                  _save();
                case 'abc':
                  _exportAbc();
                case 'clear':
                  setState(_doc.clearAll);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'save',
                enabled: !_doc.isEmpty,
                child: Text(l10n.myMelodySave),
              ),
              PopupMenuItem(
                value: 'abc',
                enabled: !_doc.isEmpty,
                child: Text(l10n.workshopExportAbc),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: !_doc.isEmpty,
                child: Text(l10n.myMelodyClear),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Full-bleed, zoomable score canvas.
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: InteractiveViewer(
                constrained: false,
                minScale: 0.4,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(300),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: InteractiveStaff(
                    score: _doc.buildScore(),
                    theme: theme,
                    staffSpace: 16,
                    // showGhostNote defaults on — the ghost previews where a
                    // tap/drag will land; match it to the armed value.
                    ghostDuration: _pendingDuration,
                    onStaffTap: _onStaffTap,
                    onElementTap: _onElementTap,
                  ),
                ),
              ),
            ),
          ),
          // Contextual selection controls.
          if (hasSelection)
            _SelectionBar(
              canTranspose: _doc.selected?.isRest == false,
              onPrev: _selectPrev,
              onNext: _selectNext,
              onUp: () => _transpose(1),
              onDown: () => _transpose(-1),
              onDelete: () => setState(_doc.deleteSelected),
            ),
          _StatusLine(
            glyph: _values.firstWhere((v) => v.base == _pendingBase).glyph,
            dotted: _dotted,
            text: _selectionText(context, l10n),
          ),
          _InputDock(
            pendingBase: _pendingBase,
            dotted: _dotted,
            accidental: _accidental,
            surface: _surface,
            onPickValue: _pickValue,
            onToggleDot: _toggleDot,
            onPickAccidental: _pickAccidental,
            onRest: _addRest,
            onSurface: (s) => setState(() => _surface = s),
            onPianoKey: _onPianoKey,
          ),
        ],
      ),
    );
  }

  String _selectionText(BuildContext context, AppLocalizations l10n) {
    final e = _doc.selected;
    if (e == null) return l10n.workshopReady;
    if (e.isRest) return l10n.workshopRest;
    final p = e.pitch!;
    final acc = p.alter > 0 ? '♯' : (p.alter < 0 ? '♭' : '');
    return '${noteNameFor(context, p.step)}$acc${p.octave}';
  }
}

/// Armed value glyph + a line of text (selection / prompt).
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.glyph,
    required this.dotted,
    required this.text,
  });

  final String glyph;
  final bool dotted;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          MusicGlyph(glyph, size: 20),
          if (dotted)
            const Text(' .', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Contextual controls for the current selection.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.canTranspose,
    required this.onPrev,
    required this.onNext,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });

  final bool canTranspose;
  final VoidCallback onPrev, onNext, onUp, onDown, onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: l10n.workshopSelectPrev,
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.workshopSelectNext,
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: canTranspose ? onUp : null,
            icon: const Icon(Icons.arrow_upward),
            tooltip: l10n.workshopUp,
          ),
          IconButton(
            onPressed: canTranspose ? onDown : null,
            icon: const Icon(Icons.arrow_downward),
            tooltip: l10n.workshopDown,
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.workshopDelete,
          ),
        ],
      ),
    );
  }
}

/// The bottom input dock: a duration/accidental glyph strip above a swappable
/// pitch surface.
class _InputDock extends StatelessWidget {
  const _InputDock({
    required this.pendingBase,
    required this.dotted,
    required this.accidental,
    required this.surface,
    required this.onPickValue,
    required this.onToggleDot,
    required this.onPickAccidental,
    required this.onRest,
    required this.onSurface,
    required this.onPianoKey,
  });

  final DurationBase pendingBase;
  final bool dotted;
  final _Accidental accidental;
  final _PitchSurface surface;
  final ValueChanged<DurationBase> onPickValue;
  final VoidCallback onToggleDot;
  final ValueChanged<_Accidental> onPickAccidental;
  final VoidCallback onRest;
  final ValueChanged<_PitchSurface> onSurface;
  final ValueChanged<int> onPianoKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Duration + modifiers strip.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final v in _values)
                    _GlyphButton(
                      selected: pendingBase == v.base,
                      onTap: () => onPickValue(v.base),
                      child: MusicGlyph(v.glyph, size: 24),
                    ),
                  _GlyphButton(
                    selected: dotted,
                    onTap: onToggleDot,
                    tooltip: l10n.workshopDot,
                    child: const Text(
                      '.',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const _DockDivider(),
                  for (final a in _Accidental.values)
                    _GlyphButton(
                      selected: accidental == a,
                      onTap: () => onPickAccidental(a),
                      child: Text(
                        _accidentalGlyph[a]!,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  const _DockDivider(),
                  _GlyphButton(
                    selected: false,
                    onTap: onRest,
                    tooltip: l10n.workshopRest,
                    child: const Icon(Icons.music_off_outlined),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Pitch surface selector.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SegmentedButton<_PitchSurface>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _PitchSurface.piano,
                    icon: const Icon(Icons.piano),
                    label: Text(l10n.inputPiano),
                  ),
                  ButtonSegment(
                    value: _PitchSurface.staff,
                    icon: const Icon(Icons.music_note),
                    label: Text(l10n.inputStaff),
                  ),
                ],
                selected: {surface},
                onSelectionChanged: (s) => onSurface(s.first),
              ),
            ),
            // The surface itself.
            if (surface == _PitchSurface.piano)
              SizedBox(
                height: 128,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: PianoKeyboard(
                    startMidi: 48, // C3
                    whiteKeyCount: 15,
                    showLabels: true,
                    onKeyTap: onPianoKey,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  l10n.workshopTapStaff,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A square, selectable glyph button used across the input dock.
class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.selected,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 44,
            child: Center(child: child),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _DockDivider extends StatelessWidget {
  const _DockDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(height: 32, child: VerticalDivider(width: 1)),
      );
}
