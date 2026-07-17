// lib/features/textbook/textbook_i18n.dart
//
// Localised titles for the textbook reader: concept titles, concept-area
// names, and grade-band narrative intros. The concept map stays pure English
// data (for the coverage analysis); these ARB-backed lookups localise the UI.

import 'package:comet_beat/core/curriculum/concept_map.dart';
import 'package:comet_beat/l10n/app_localizations.dart';

/// Localised title for a concept id (falls back to the English map label).
String conceptTitle(AppLocalizations l10n, String id) => switch (id) {
      'pulse' => l10n.conceptPulse,
      'high_low' => l10n.conceptHighLow,
      'melody_direction' => l10n.conceptMelodyDirection,
      'same_different' => l10n.conceptSameDifferent,
      'loud_soft' => l10n.conceptLoudSoft,
      'fast_slow' => l10n.conceptFastSlow,
      'long_short' => l10n.conceptLongShort,
      'count_sounds' => l10n.conceptCountSounds,
      'treble_staff' => l10n.conceptTrebleStaff,
      'ledger_middle_c' => l10n.conceptLedgerMiddleC,
      'note_values' => l10n.conceptNoteValues,
      'rests' => l10n.conceptRests,
      'dotted_notes' => l10n.conceptDottedNotes,
      'beats_per_bar' => l10n.conceptBeatsPerBar,
      'time_signature' => l10n.conceptTimeSignature,
      'strong_weak_beat' => l10n.conceptStrongWeakBeat,
      'dynamics_marks' => l10n.conceptDynamicsMarks,
      'tempo_terms' => l10n.conceptTempoTerms,
      'rhythm_echo' => l10n.conceptRhythmEcho,
      'steps_skips' => l10n.conceptStepsSkips,
      'c_major_scale' => l10n.conceptCMajorScale,
      'major_minor_ear' => l10n.conceptMajorMinorEar,
      'song_form' => l10n.conceptSongForm,
      'bass_clef' => l10n.conceptBassClef,
      'grand_staff' => l10n.conceptGrandStaff,
      'clef_signs' => l10n.conceptClefSigns,
      'accidentals' => l10n.conceptAccidentals,
      'enharmonics' => l10n.conceptEnharmonics,
      'whole_half_step' => l10n.conceptWholeHalfStep,
      'key_signatures' => l10n.conceptKeySignatures,
      'major_scales' => l10n.conceptMajorScales,
      'intervals' => l10n.conceptIntervals,
      'triads' => l10n.conceptTriads,
      'ties_slurs' => l10n.conceptTiesSlurs,
      'articulation' => l10n.conceptArticulation,
      'beams' => l10n.conceptBeams,
      'anacrusis' => l10n.conceptAnacrusis,
      'compound_meter' => l10n.conceptCompoundMeter,
      'syncopation' => l10n.conceptSyncopation,
      'triplets' => l10n.conceptTriplets,
      'circle_of_fifths' => l10n.conceptCircleOfFifths,
      'minor_scales' => l10n.conceptMinorScales,
      'chord_qualities' => l10n.conceptChordQualities,
      'seventh_chords' => l10n.conceptSeventhChords,
      'chord_symbols' => l10n.conceptChordSymbols,
      'cadences' => l10n.conceptCadences,
      'harmonic_function' => l10n.conceptHarmonicFunction,
      'roman_numerals' => l10n.conceptRomanNumerals,
      'melodic_dictation' => l10n.conceptMelodicDictation,
      'phrasing_qa' => l10n.conceptPhrasingQa,
      'musical_form' => l10n.conceptMusicalForm,
      'modulation' => l10n.conceptModulation,
      'inversions' => l10n.conceptInversions,
      'transposing_instruments' => l10n.conceptTransposingInstruments,
      'tenor_clef' => l10n.conceptTenorClef,
      'satb_voices' => l10n.conceptSatbVoices,
      'score_reading' => l10n.conceptScoreReading,
      'ornaments' => l10n.conceptOrnaments,
      'modes' => l10n.conceptModes,
      'instrument_families' => l10n.conceptInstrumentFamilies,
      'reading_fluency' => l10n.conceptReadingFluency,
      'aural_memory' => l10n.conceptAuralMemory,
      'sing_what_you_hear' => l10n.conceptSingWhatYouHear,
      'play_keyboard' => l10n.conceptPlayKeyboard,
      'play_cello' => l10n.conceptPlayCello,
      'play_guitar' => l10n.conceptPlayGuitar,
      'play_percussion' => l10n.conceptPlayPercussion,
      'compose' => l10n.conceptCompose,
      'arrange_loops' => l10n.conceptArrangeLoops,
      'learn_songs' => l10n.conceptLearnSongs,
      _ => id,
    };

/// The textbook's OWN teaching paragraph for a concept — richer than the game
/// primer, in the book's voice, our own words. Returns null where none is
/// authored yet (the reader then shows no prose block), so coverage grows
/// concept by concept. Localised (de/en).
String? conceptProse(AppLocalizations l10n, String id) => switch (id) {
      'intervals' => l10n.proseIntervals,
      'triads' => l10n.proseTriads,
      'key_signatures' => l10n.proseKeySignatures,
      'enharmonics' => l10n.proseEnharmonics,
      'circle_of_fifths' => l10n.proseCircleOfFifths,
      'minor_scales' => l10n.proseMinorScales,
      'seventh_chords' => l10n.proseSeventhChords,
      'cadences' => l10n.proseCadences,
      'harmonic_function' => l10n.proseHarmonicFunction,
      'roman_numerals' => l10n.proseRomanNumerals,
      'modulation' => l10n.proseModulation,
      'modes' => l10n.proseModes,
      'syncopation' => l10n.proseSyncopation,
      'triplets' => l10n.proseTriplets,
      'song_form' => l10n.proseSongForm,
      'musical_form' => l10n.proseMusicalForm,
      'transposing_instruments' => l10n.proseTransposingInstruments,
      _ => null,
    };

/// Localised name for a concept area (the sub-headers in the reader).
String areaName(AppLocalizations l10n, ConceptArea area) => switch (area) {
      ConceptArea.pulse => l10n.areaPulse,
      ConceptArea.reading => l10n.areaReading,
      ConceptArea.duration => l10n.areaDuration,
      ConceptArea.meter => l10n.areaMeter,
      ConceptArea.dynamics => l10n.areaDynamics,
      ConceptArea.tempo => l10n.areaTempo,
      ConceptArea.pitch => l10n.areaPitch,
      ConceptArea.scales => l10n.areaScales,
      ConceptArea.intervals => l10n.areaIntervals,
      ConceptArea.chords => l10n.areaChords,
      ConceptArea.harmony => l10n.areaHarmony,
      ConceptArea.articulation => l10n.areaArticulation,
      ConceptArea.transpose => l10n.areaTranspose,
      ConceptArea.form => l10n.areaForm,
      ConceptArea.timbre => l10n.areaTimbre,
      ConceptArea.technique => l10n.areaTechnique,
      ConceptArea.aural => l10n.areaAural,
      ConceptArea.creating => l10n.areaCreating,
      ConceptArea.repertoire => l10n.areaRepertoire,
    };

/// The narrative intro paragraph for a grade band.
String bandIntro(AppLocalizations l10n, GradeBand band) => switch (band) {
      GradeBand.g12 => l10n.textbookBandG12,
      GradeBand.g34 => l10n.textbookBandG34,
      GradeBand.g56 => l10n.textbookBandG56,
      GradeBand.g78 => l10n.textbookBandG78,
      GradeBand.g910 => l10n.textbookBandG910,
    };

/// Localised short label for a grade band (the section headers).
String bandLabel(AppLocalizations l10n, GradeBand band) => switch (band) {
      GradeBand.g12 => l10n.textbookGradesG12,
      GradeBand.g34 => l10n.textbookGradesG34,
      GradeBand.g56 => l10n.textbookGradesG56,
      GradeBand.g78 => l10n.textbookGradesG78,
      GradeBand.g910 => l10n.textbookGradesG910,
    };
