// lib/core/note_naming.dart
//
// The note-naming convention the learner sees, chosen independently of the UI
// language. `auto` follows the app language — German shows H for the natural B,
// English shows B — matching how the note names are translated in the ARB.

enum NoteNaming { auto, english, germanH, solfege }
