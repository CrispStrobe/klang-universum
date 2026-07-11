// lib/features/games/composition/my_melody_screen.dart
//
// "Meine Melodie" — the composing sandbox: tap the staff to write notes,
// hear each one as you place it, then play your melody back. No score, no
// stars, no wrong answers — free creation is the point (and the child is
// reading and writing real notation the whole time).

import 'package:flutter/material.dart';
import 'package:partitura/partitura.dart'
    show
        Clef,
        DurationBase,
        InteractiveStaff,
        Measure,
        NoteDuration,
        NoteElement,
        PartituraTheme,
        RestElement,
        Score,
        StaffTarget;
import 'package:provider/provider.dart';

import '../../../core/services/audio_service.dart';
import '../../../l10n/app_localizations.dart';

class MyMelodyScreen extends StatefulWidget {
  const MyMelodyScreen({super.key});

  static const maxNotes = 12;

  @override
  State<MyMelodyScreen> createState() => _MyMelodyScreenState();
}

class _MyMelodyScreenState extends State<MyMelodyScreen> {
  final List<NoteElement> _notes = [];
  var _nextId = 0;

  Score get _score => Score(
        clef: Clef.treble,
        measures: [
          Measure(List.of(_notes)),
          // Whole-rest measure keeps the tappable staff wide.
          if (_notes.length < 6)
            Measure(const [RestElement(NoteDuration(DurationBase.whole))]),
        ],
      );

  void _onStaffTap(StaffTarget target) {
    if (_notes.length >= MyMelodyScreen.maxNotes) return;
    final pitch = target.pitchFor(Clef.treble);
    context.read<AudioService>().playMidiNote(pitch.midiNumber, ms: 400);
    setState(() {
      _notes.add(NoteElement.note(
        pitch,
        const NoteDuration(DurationBase.quarter),
        id: 'm${_nextId++}',
      ));
    });
  }

  void _play() {
    if (_notes.isEmpty) return;
    context.read<AudioService>().playSequence([
      for (final note in _notes) (note.pitches.first.midiNumber, 400),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final full = _notes.length >= MyMelodyScreen.maxNotes;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gameMyMelody)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                full ? l10n.myMelodyFull : l10n.myMelodyPrompt,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: InteractiveStaff(
                        score: _score,
                        theme: PartituraTheme.kids,
                        staffSpace: 14,
                        ghostDuration:
                            const NoteDuration(DurationBase.quarter),
                        onStaffTap: _onStaffTap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _notes.isEmpty ? null : _play,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.myMelodyPlay),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _notes.isEmpty
                        ? null
                        : () => setState(() => _notes.removeLast()),
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.myMelodyUndo),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _notes.isEmpty
                        ? null
                        : () => setState(_notes.clear),
                    icon: const Icon(Icons.delete_outline),
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
}
