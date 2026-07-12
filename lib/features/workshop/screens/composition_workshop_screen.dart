// lib/features/workshop/screens/composition_workshop_screen.dart
//
// "Kompositions-Werkstatt" / "Composition Workshop" — a real little score
// editor (out of the minigames, in the Workshop section). Unlike the My Melody
// sandbox this lets the child:
//   • pick a time signature (2/4 · 3/4 · 4/4) — bar-lines are drawn automatically,
//   • pick a note value (whole / half / quarter / eighth) before placing,
//   • tap the staff to add a note, tap a note to select it and re-pitch or
//     delete it (edit in place),
//   • hear it back with real durations and save it to the Song Book as MusicXML
//     (opens in MuseScore & co.).

// Material's Stepper also exports a `Step`; partitura's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/widgets/music_glyph.dart';
import 'package:partitura/partitura.dart';
import 'package:provider/provider.dart';

/// A note the child has written: its pitch, its value, and a stable id (so it
/// can be selected and edited).
class _WNote {
  _WNote(this.pitch, this.base, this.id);
  Pitch pitch;
  DurationBase base;
  final String id;
}

/// A choosable note value: glyph + duration + length in quarter-beats.
typedef _Value = ({String glyph, DurationBase base, double beats});

const _values = <_Value>[
  (glyph: Smufl.wholeNote, base: DurationBase.whole, beats: 4),
  (glyph: Smufl.halfNote, base: DurationBase.half, beats: 2),
  (glyph: Smufl.quarterNote, base: DurationBase.quarter, beats: 1),
  (glyph: Smufl.eighthNote, base: DurationBase.eighth, beats: 0.5),
];

double _beatsOf(DurationBase base) =>
    _values.firstWhere((v) => v.base == base).beats;

class CompositionWorkshopScreen extends StatefulWidget {
  const CompositionWorkshopScreen({super.key});

  static const maxNotes = 32;

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
  @override
  int get noteCount => _notes.length;

  @override
  int get barCount => _measures().length;

  final List<_WNote> _notes = [];
  var _nextId = 0;
  DurationBase _pending = DurationBase.quarter; // the value about to be placed
  TimeSignature _timeSig = TimeSignature.fourFour;
  String? _selected; // id of the note being edited

  /// Show low material (a cello's C) in the bass clef instead of a ledger tower.
  Clef get _clef =>
      _notes.any((n) => n.pitch.midiNumber < 55) ? Clef.bass : Clef.treble;

  double get _beatsPerBar => _timeSig.beats.toDouble(); // /4 metres: quarters

  /// Pack the flat note list into bars for automatic bar-lines. A note that
  /// won't fit the current bar starts a new one (kid-simple: no splitting/ties).
  List<Measure> _measures() {
    if (_notes.isEmpty) {
      return const [
        Measure([RestElement(NoteDuration(DurationBase.whole))]),
      ];
    }
    final bars = <Measure>[];
    var current = <MusicElement>[];
    var acc = 0.0;
    for (final n in _notes) {
      final b = _beatsOf(n.base);
      if (acc > 0 && acc + b > _beatsPerBar + 1e-6) {
        bars.add(Measure(current));
        current = [];
        acc = 0;
      }
      current.add(NoteElement.note(n.pitch, NoteDuration(n.base), id: n.id));
      acc += b;
    }
    if (current.isNotEmpty) bars.add(Measure(current));
    return bars;
  }

  Score get _score => Score(
        clef: _clef,
        timeSignature: _timeSig,
        measures: _measures(),
      );

  void _onStaffTap(StaffTarget target) {
    final pitch = target.pitchFor(_clef);
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 400);
    setState(() {
      final selected = _selected;
      if (selected != null) {
        _notes.firstWhere((n) => n.id == selected).pitch = pitch;
        _selected = null;
      } else if (_notes.length < CompositionWorkshopScreen.maxNotes) {
        _notes.add(_WNote(pitch, _pending, 'w${_nextId++}'));
      }
    });
  }

  void _onNoteTap(String id) => setState(
        () => _selected = _selected == id ? null : id,
      );

  void _deleteSelected() {
    final selected = _selected;
    if (selected == null) return;
    setState(() {
      _notes.removeWhere((n) => n.id == selected);
      _selected = null;
    });
  }

  void _play() {
    if (_notes.isEmpty) return;
    context.read<AudioService>().playSequence([
      for (final n in _notes)
        (n.pitch.midiNumber, (_beatsOf(n.base) * 480).round()),
    ]);
  }

  // Export the score as ABC notation (partitura's scoreToAbc) — a compact text
  // form that pastes into ABC tools and back into the Song Book importer.
  Future<void> _exportAbc() async {
    if (_notes.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final abc = scoreToAbc(_score);
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
    if (_notes.isEmpty) return;
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
        musicXml: scoreToMusicXml(_score),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.myMelodySaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = PartituraTheme.kids.copyWith(
      elementColors: {
        if (_selected != null) _selected!: Colors.amber,
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workshopComposeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.abc),
            tooltip: l10n.workshopExportAbc,
            onPressed: _notes.isEmpty ? null : _exportAbc,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Time signature + note value pickers.
              Row(
                children: [
                  Text(
                    l10n.workshopTimeSignature,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 8),
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
                    selected: {_timeSig},
                    onSelectionChanged: (s) =>
                        setState(() => _timeSig = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final v in _values)
                    ChoiceChip(
                      avatar: MusicGlyph(v.glyph, size: 22),
                      label: Text(_beatsLabel(l10n, v.beats)),
                      selected: _pending == v.base,
                      onSelected: (_) => setState(() => _pending = v.base),
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
                        score: _score,
                        theme: theme,
                        staffSpace: 14,
                        onStaffTap: _onStaffTap,
                        onElementTap: _onNoteTap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selected == null ? l10n.workshopHint : l10n.workshopEditHint,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    onPressed: _notes.isEmpty ? null : _play,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.myMelodyPlay),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _notes.isEmpty ? null : _save,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l10n.myMelodySave),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _selected == null ? null : _deleteSelected,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.workshopDelete),
                  ),
                  TextButton.icon(
                    onPressed: _notes.isEmpty
                        ? null
                        : () => setState(() {
                              _notes.removeLast();
                              _selected = null;
                            }),
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.myMelodyUndo),
                  ),
                  TextButton.icon(
                    onPressed: _notes.isEmpty
                        ? null
                        : () => setState(() {
                              _notes.clear();
                              _selected = null;
                            }),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(l10n.myMelodyClear),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _beatsLabel(AppLocalizations l10n, double beats) {
    if (beats == 0.5) return l10n.halfBeat;
    return l10n.beatsCount(beats.toInt());
  }
}
