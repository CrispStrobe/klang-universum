// lib/features/workshop/model/score_document.dart
//
// The editable document behind the Composition Workshop. partitura's Score is
// an immutable value tree with no in-place editing, so the editor keeps its own
// flat, mutable list of [EditorElement]s and rebuilds an immutable [Score] on
// demand (packing the flat list into bar-lined measures). All mutations go
// through commands that snapshot first, giving multi-level undo/redo.
//
// This is the foundation the Workshop grows on: later phases add ties, tuplets,
// a second voice, dynamics and more as new fields/commands here, without the
// screen having to know how a Score is assembled.

import 'package:partitura/partitura.dart';

/// One editable event in the flat stream: a note (single pitch for now; chords
/// come later) or a rest, with a stable [id] so it can be selected and edited.
class EditorElement {
  const EditorElement.note(Pitch this.pitch, this.duration, {required this.id})
      : isRest = false;

  const EditorElement.rest(this.duration, {required this.id})
      : pitch = null,
        isRest = true;

  /// The pitch, or null for a rest.
  final Pitch? pitch;
  final NoteDuration duration;
  final String id;
  final bool isRest;

  /// This event as an immutable partitura element.
  MusicElement toElement() => isRest
      ? RestElement(duration, id: id)
      : NoteElement.note(pitch!, duration, id: id);

  EditorElement withPitch(Pitch pitch) =>
      EditorElement.note(pitch, duration, id: id);

  EditorElement withDuration(NoteDuration duration) => isRest
      ? EditorElement.rest(duration, id: id)
      : EditorElement.note(pitch!, duration, id: id);
}

/// An undo/redo snapshot of the document's mutable state.
class _Snapshot {
  const _Snapshot(this.elements, this.timeSignature, this.keySignature);
  final List<EditorElement> elements;
  final TimeSignature timeSignature;
  final KeySignature keySignature;
}

/// The editable Workshop document: an ordered element stream plus the
/// document-level time/key signature, a selection, and undo/redo.
class ScoreDocument {
  ScoreDocument({
    this.timeSignature = TimeSignature.fourFour,
    this.keySignature = const KeySignature(0),
  });

  final List<EditorElement> _elements = [];
  TimeSignature timeSignature;
  KeySignature keySignature;

  String? _selectedId;
  var _nextId = 0;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  // ---- reads -------------------------------------------------------------

  List<EditorElement> get elements => List.unmodifiable(_elements);
  int get length => _elements.length;
  bool get isEmpty => _elements.isEmpty;
  String? get selectedId => _selectedId;

  EditorElement? get selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final e in _elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Show low material (a cello's low C) in the bass clef instead of a tower of
  /// ledger lines under a treble staff.
  Clef get clef => _elements.any((e) => !e.isRest && e.pitch!.midiNumber < 55)
      ? Clef.bass
      : Clef.treble;

  String _newId() => 'w${_nextId++}';

  // ---- history -----------------------------------------------------------

  void _snapshot() {
    _undo.add(_Snapshot(List.of(_elements), timeSignature, keySignature));
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    _elements
      ..clear()
      ..addAll(s.elements);
    timeSignature = s.timeSignature;
    keySignature = s.keySignature;
    if (!_elements.any((e) => e.id == _selectedId)) _selectedId = null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(List.of(_elements), timeSignature, keySignature));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(List.of(_elements), timeSignature, keySignature));
    _restore(_redo.removeLast());
  }

  // ---- commands ----------------------------------------------------------

  /// Append a note. Returns the new element's id. Does not change the
  /// selection, so repeated staff taps place a run of notes fluently.
  String insertNote(Pitch pitch, NoteDuration duration) {
    _snapshot();
    final id = _newId();
    _elements.add(EditorElement.note(pitch, duration, id: id));
    return id;
  }

  /// Append a rest. Returns the new element's id.
  String insertRest(NoteDuration duration) {
    _snapshot();
    final id = _newId();
    _elements.add(EditorElement.rest(duration, id: id));
    return id;
  }

  /// Re-pitch the selected element (no-op if nothing / a rest is selected).
  void repitchSelected(Pitch pitch) {
    final i = _indexOfSelected();
    if (i < 0 || _elements[i].isRest) return;
    _snapshot();
    _elements[i] = _elements[i].withPitch(pitch);
  }

  /// Change the selected element's duration (note or rest).
  void setDurationOfSelected(NoteDuration duration) {
    final i = _indexOfSelected();
    if (i < 0) return;
    _snapshot();
    _elements[i] = _elements[i].withDuration(duration);
  }

  void deleteSelected() {
    final i = _indexOfSelected();
    if (i < 0) return;
    _snapshot();
    _elements.removeAt(i);
    _selectedId = null;
  }

  void clearAll() {
    if (_elements.isEmpty) return;
    _snapshot();
    _elements.clear();
    _selectedId = null;
  }

  void setTimeSignature(TimeSignature value) {
    if (value == timeSignature) return;
    _snapshot();
    timeSignature = value;
  }

  void setKeySignature(KeySignature value) {
    if (value == keySignature) return;
    _snapshot();
    keySignature = value;
  }

  /// Toggle selection of [id] (tapping the selected element clears it).
  void toggleSelected(String id) => _selectedId = _selectedId == id ? null : id;

  void clearSelection() => _selectedId = null;

  int _indexOfSelected() => _elements.indexWhere((e) => e.id == _selectedId);

  // ---- rendering ---------------------------------------------------------

  /// Pack the flat element stream into bar-lined [Measure]s. A note that would
  /// overflow the current bar starts a new one (no splitting/tying yet — that
  /// arrives with P2). Empty document → a single whole-rest bar so the staff
  /// stays wide and tappable.
  Score buildScore() {
    if (_elements.isEmpty) {
      return Score(
        clef: clef,
        keySignature: keySignature,
        timeSignature: timeSignature,
        measures: const [
          Measure([RestElement(NoteDuration(DurationBase.whole))]),
        ],
      );
    }

    final zero = Fraction(0, 1);
    final capacity = timeSignature.toFraction();
    final bars = <Measure>[];
    var current = <MusicElement>[];
    var filled = zero;

    for (final e in _elements) {
      final d = e.duration.toFraction();
      if (filled > zero && (filled + d) > capacity) {
        bars.add(Measure(current));
        current = [];
        filled = zero;
      }
      current.add(e.toElement());
      filled = filled + d;
    }
    if (current.isNotEmpty) bars.add(Measure(current));

    return Score(
      clef: clef,
      keySignature: keySignature,
      timeSignature: timeSignature,
      measures: bars,
    );
  }

  int get barCount => buildScore().measures.length;
}
