// lib/core/audio/multi_sample_instrument.dart
//
// A sampled Tracker instrument with a DIFFERENT sample per note-range — the
// XM/IT "keymap" model. Record (or borrow) a few notes across the range, map
// each to a key zone, and every played note resamples the NEAREST zone instead
// of stretching one sample across octaves. That keeps the timbre natural: a
// sample pitched a fifth sounds fine, but two octaves up turns to chipmunk, so
// spreading a handful of zones across the keyboard is how real samplers stay
// realistic. Pure Dart, deterministic. TRACKER_IDEAS §B ("multi-sample
// instruments"). Mirrors [SampleInstrument.renderChannel] but selects a zone
// per note-run.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/envelope.dart';
import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:comet_beat/core/audio/tracker_engine.dart';

/// One key-range → sample mapping. [sample] plays at true pitch when the note
/// equals [baseMidi]; it is resampled for any other note in `[loMidi, hiMidi]`.
class SampleZone {
  const SampleZone({
    required this.sample,
    required this.baseMidi,
    this.loMidi = 0,
    this.hiMidi = 127,
  });

  final Float64List sample;
  final int baseMidi;
  final int loMidi;
  final int hiMidi;

  /// True when [midi] falls inside this zone's key range (inclusive).
  bool covers(int midi) => midi >= loMidi && midi <= hiMidi;
}

/// A sampled instrument backed by several [SampleZone]s.
class MultiSampleInstrument implements TrackerInstrument {
  const MultiSampleInstrument(
    this.id,
    this.zones, {
    this.envelope = Envelope.declick,
  });

  /// Builds an instrument from bare `(sample, baseMidi)` points, auto-assigning
  /// each a key range that reaches the midpoint between adjacent base notes —
  /// the usual "map recorded notes across the keyboard". The lowest zone extends
  /// down to MIDI 0 and the highest up to 127, so every note is covered. Points
  /// need not be pre-sorted.
  factory MultiSampleInstrument.mapped(
    String id,
    List<({Float64List sample, int baseMidi})> points, {
    Envelope envelope = Envelope.declick,
  }) {
    final sorted = [...points]
      ..sort((a, b) => a.baseMidi.compareTo(b.baseMidi));
    final zones = <SampleZone>[];
    for (var i = 0; i < sorted.length; i++) {
      final lo =
          i == 0 ? 0 : ((sorted[i - 1].baseMidi + sorted[i].baseMidi) ~/ 2) + 1;
      final hi = i == sorted.length - 1
          ? 127
          : (sorted[i].baseMidi + sorted[i + 1].baseMidi) ~/ 2;
      zones.add(
        SampleZone(
          sample: sorted[i].sample,
          baseMidi: sorted[i].baseMidi,
          loMidi: lo,
          hiMidi: hi,
        ),
      );
    }
    return MultiSampleInstrument(id, zones, envelope: envelope);
  }

  @override
  final String id;
  final List<SampleZone> zones;

  /// A per-note volume/pitch envelope shared across zones (default declick).
  final Envelope envelope;

  /// The zone that plays [midi]: the first zone whose range covers it, else the
  /// zone with the nearest [SampleZone.baseMidi] (so a note above/below every
  /// range still sounds, just resampled further). Null only when [zones] is
  /// empty.
  SampleZone? zoneFor(int midi) {
    SampleZone? nearest;
    var bestDist = 1 << 30;
    for (final z in zones) {
      if (z.covers(midi)) return z;
      final d = (z.baseMidi - midi).abs();
      if (d < bestDist) {
        bestDist = d;
        nearest = z;
      }
    }
    return nearest;
  }

  @override
  Float64List renderChannel(List<TrackerCell> cells, TrackerTiming timing) {
    final out = Float64List(timing.totalSamples);
    if (zones.isEmpty) return out;
    var startStep = 0;
    for (final (midi, steps) in cellRuns(cells)) {
      if (midi != null) {
        final zone = zoneFor(midi);
        if (zone != null && zone.sample.isNotEmpty) {
          final startSample = timing.stepStartSample(startStep);
          final runSamples =
              timing.stepStartSample(startStep + steps) - startSample;
          final baseRatio =
              midiToFrequency(midi) / midiToFrequency(zone.baseMidi);
          final maxOut = min(runSamples, out.length - startSample);
          // A pitch envelope glides the resample ratio; else a fixed ratio.
          final buf = envelope.pitchStart != 0 && maxOut > 0
              ? resampleGlide(
                  zone.sample,
                  ratioStart: baseRatio * pow(2, envelope.pitchStart / 12),
                  ratioEnd: baseRatio,
                  glideSamples: (envelope.pitchTime * kSampleRate).round(),
                  outLen: maxOut,
                )
              : resampleCubic(zone.sample, baseRatio);
          final n = min(min(buf.length, runSamples), out.length - startSample);
          if (n > 0) {
            final voiced = applyEnvelope(
              Float64List.sublistView(buf, 0, n),
              envelope,
            );
            for (var i = 0; i < n; i++) {
              out[startSample + i] = voiced[i];
            }
          }
        }
      }
      startStep += steps;
    }
    return out;
  }
}
