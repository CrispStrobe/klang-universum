// lib/core/audio/transcription/crepe.dart
//
// W-CREPE (adapter shell) — CREPE (Kim et al. 2018, MIT) as a neural F0 estimator
// that drops into the router behind the shared PitchTrack contract
// (route.dart's F0Estimator), a more accurate + timbre-robust alternative to the
// built-in pure-Dart pYIN (fixes sung-voice octave-doubling / drift).
//
// STATUS: everything here — resampling, framing, per-frame normalisation, and
// the 360-bin activation → f0 DECODING — is fully implemented and unit-tested
// (see crepe_test.dart). The ONLY thing a model worker must finish is publishing
// the CREPE ONNX and confirming the input/output tensor names below against that
// export (a one-line change if they differ), then wiring crepe_model_store.dart's
// URL. Inference uses the SAME `onnx_runtime_dart` API as basic_pitch.dart.
//
// Web-safe: like basic_pitch.dart this takes a preloaded [OnnxModel] and never
// imports dart:io (model download/caching lives in crepe_model_store.dart). The
// app injects it as `transcribeAuto(f0: (m, sr) => crepeF0(m, sampleRate: sr,
// model: model))`.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/resample.dart';
import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

const int _crepeRate = 16000; // CREPE operates on 16 kHz mono
const int _frameSize = 1024; // 1024-sample frames
const int _bins = 360; // 360-bin pitch activation (20-cent resolution)

// CREPE's bin→cents mapping: cents[i] = 1997.379… + 20·i, and
// frequency = 10 · 2^(cents/1200). Bin 0 ≈ 31.7 Hz (just under C1), bin 359 ≈
// 1975.5 Hz.
const double _centsBase = 1997.3794084376191;
const double _centsPerBin = 20;

// TODO(model worker): confirm these against the published CREPE ONNX export.
const String _inputName = 'input';
const String _outputName = 'output';

/// Estimate F0 over [mono] with CREPE, emitting the shared [PitchTrack]. [model]
/// is a preloaded CREPE ONNX (see crepe_model_store.dart). A frame slides by
/// [hopMs] ms; [confidenceFloor] gates a frame unvoiced (`f0Hz == 0`) when the
/// activation peak is weaker than it.
Future<PitchTrack> crepeF0(
  Float64List mono, {
  required OnnxModel model,
  int sampleRate = 44100,
  double hopMs = 10,
  double confidenceFloor = 0.5,
}) async {
  final audio = sampleRate == _crepeRate
      ? mono
      : resampleLinear(mono, sampleRate / _crepeRate);
  final hop = math.max(1, (hopMs * _crepeRate / 1000).round());
  if (audio.length < _frameSize) return const [];

  final track = <PitchFrame>[];
  final frame = Float32List(_frameSize);
  for (var start = 0; start + _frameSize <= audio.length; start += hop) {
    normalizeFrameInto(audio, start, frame);
    final input = Tensor.float(frame, [1, _frameSize]);
    final out = model.run({_inputName: input}, const [_outputName]);
    final t = out[_outputName]!;
    final data = t.f ?? t.asFloatList();
    final decoded = decodeActivation(data);
    final timeMs = (start + _frameSize / 2) / _crepeRate * 1000;
    final voiced = decoded.confidence >= confidenceFloor;
    track.add(
      (
        timeMs: timeMs,
        f0Hz: voiced ? decoded.f0Hz : 0.0,
        voicedProb: decoded.confidence.clamp(0.0, 1.0),
      ),
    );
  }
  return track;
}

/// Copy [frameSize] samples starting at [start] into [out], normalised to
/// zero-mean / unit-standard-deviation — CREPE's expected per-frame input.
void normalizeFrameInto(Float64List audio, int start, Float32List out) {
  var mean = 0.0;
  for (var i = 0; i < _frameSize; i++) {
    mean += audio[start + i];
  }
  mean /= _frameSize;
  var varSum = 0.0;
  for (var i = 0; i < _frameSize; i++) {
    final d = audio[start + i] - mean;
    varSum += d * d;
  }
  final std = math.sqrt(varSum / _frameSize);
  final inv = std > 1e-8 ? 1.0 / std : 0.0;
  for (var i = 0; i < _frameSize; i++) {
    out[i] = (audio[start + i] - mean) * inv;
  }
}

/// Decode a 360-bin CREPE [activation] into an f0 + confidence: a local
/// weighted-average of cents over ±4 bins around the peak (CREPE's own
/// smoothing), then cents → Hz. Confidence is the peak activation.
({double f0Hz, double confidence}) decodeActivation(List<double> activation) {
  if (activation.length < _bins) return (f0Hz: 0, confidence: 0);
  var peak = 0;
  var peakVal = activation[0];
  for (var i = 1; i < _bins; i++) {
    if (activation[i] > peakVal) {
      peakVal = activation[i];
      peak = i;
    }
  }
  final lo = math.max(0, peak - 4);
  final hi = math.min(_bins - 1, peak + 4);
  var num = 0.0, den = 0.0;
  for (var i = lo; i <= hi; i++) {
    final cents = _centsBase + _centsPerBin * i;
    num += activation[i] * cents;
    den += activation[i];
  }
  if (den <= 0) return (f0Hz: 0, confidence: peakVal.clamp(0.0, 1.0));
  final cents = num / den;
  final f0 = 10.0 * math.pow(2, cents / 1200).toDouble();
  return (f0Hz: f0, confidence: peakVal.clamp(0.0, 1.0));
}

/// The Hz a single [bin] index maps to — exposed for tests / calibration.
double binToHz(int bin) =>
    10.0 * math.pow(2, (_centsBase + _centsPerBin * bin) / 1200).toDouble();
