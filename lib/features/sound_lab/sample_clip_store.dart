// A persistent "My Samples" library: short audio clips (mono PCM + a sample
// rate) saved across sessions. The Voice Lab saves the voice you record and
// shape here; the module Sample Extractor drops the samples it pulls out of
// tracker files here. Both then recall them without a round-trip through disk.
//
// Storage: each clip's float PCM is quantized to 16-bit and base64'd, so the
// whole library is one JSON string in SharedPreferences. The encode/decode
// pair is pure (testable without a platform).

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// One saved clip = a name, its sample rate, and mono float PCM ([-1, 1]).
class SampleClip {
  const SampleClip({
    required this.name,
    required this.sampleRate,
    required this.pcm,
    this.source,
  });

  final String name;
  final int sampleRate;
  final Float64List pcm;

  /// Where it came from (e.g. a module title) — display-only, may be null.
  final String? source;

  Map<String, dynamic> toJson() => {
        'name': name,
        'rate': sampleRate,
        if (source != null) 'source': source,
        'pcm': base64Encode(_floatToInt16Bytes(pcm)),
      };

  static SampleClip? fromJson(Map<String, dynamic> j) {
    final name = j['name'];
    final rate = j['rate'];
    final pcm = j['pcm'];
    if (name is! String || rate is! int || pcm is! String) return null;
    try {
      return SampleClip(
        name: name,
        sampleRate: rate,
        pcm: _int16BytesToFloat(base64Decode(pcm)),
        source: j['source'] is String ? j['source'] as String : null,
      );
    } catch (_) {
      return null;
    }
  }
}

Uint8List _floatToInt16Bytes(Float64List pcm) {
  final bytes = Uint8List(pcm.length * 2);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < pcm.length; i++) {
    view.setInt16(
      i * 2,
      (pcm[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}

Float64List _int16BytesToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, n * 2);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Serializes a clip list to a JSON string.
String encodeClips(List<SampleClip> clips) =>
    jsonEncode([for (final c in clips) c.toJson()]);

/// Parses a clip list; skips malformed entries, returns empty (never throws)
/// for null/blank/invalid input.
List<SampleClip> decodeClips(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map)
          if (SampleClip.fromJson(e.cast<String, dynamic>()) case final c?) c,
    ];
  } catch (_) {
    return const [];
  }
}

/// SharedPreferences-backed persistence of the "My Samples" library.
class SampleClipStore {
  static const _key = 'sound_lab_samples';

  Future<List<SampleClip>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeClips(prefs.getString(_key));
  }

  /// Adds [clip]; a save under an existing name overwrites it. Newest last.
  Future<List<SampleClip>> save(SampleClip clip) async {
    final list = [...await load()]..removeWhere((c) => c.name == clip.name);
    list.add(clip);
    await _write(list);
    return list;
  }

  Future<List<SampleClip>> delete(String name) async {
    final list = [...await load()]..removeWhere((c) => c.name == name);
    await _write(list);
    return list;
  }

  Future<void> _write(List<SampleClip> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encodeClips(list));
  }
}
