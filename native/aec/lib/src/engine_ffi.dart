// Low-level, synchronous 1:1 binding to the native `aec_engine_*` duplex host.
//
// This is the layer the tests drive directly: the headless unit test uses
// [create] + [reference] + [pump] + [read]; the live tests add [startNull] /
// [startNamed] + [readRaw]. The streaming, app-facing [NativeAecEngine] in
// aec_engine.dart wraps this and adds a Timer-driven `cleaned` stream.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

typedef _CreateC = Pointer<Void> Function(Int32, Int32);
typedef _CreateD = Pointer<Void> Function(int, int);
typedef _StartC = Int32 Function(Pointer<Void>);
typedef _StartD = int Function(Pointer<Void>);
typedef _StartNamedC = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _StartNamedD = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _RefPumpC = Void Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _RefPumpD = void Function(Pointer<Void>, Pointer<Int16>, int);
typedef _ReadC = Int32 Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _ReadD = int Function(Pointer<Void>, Pointer<Int16>, int);
typedef _SetPeriodC = Void Function(Pointer<Void>, Int32);
typedef _SetPeriodD = void Function(Pointer<Void>, int);
typedef _StopC = Int32 Function(Pointer<Void>);
typedef _StopD = int Function(Pointer<Void>);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);

/// Thin synchronous wrapper over one native `AecEngine`.
class AecEngineFfi {
  AecEngineFfi._(this._lib, this._handle, this.sampleRate, this.frame)
      : _io = calloc<Int16>(sampleRate); // reusable transfer buffer (~1 s)

  /// Open the library and create an engine (does not start a device).
  factory AecEngineFfi.create({
    int sampleRate = 44100,
    int frame = 256,
    String? libraryPath,
  }) {
    final lib = openAecLibrary(libraryPath);
    final create = lib.lookupFunction<_CreateC, _CreateD>('aec_engine_create');
    final handle = create(sampleRate, frame);
    if (handle == nullptr) {
      throw StateError('aec_engine_create($sampleRate, $frame) failed');
    }
    return AecEngineFfi._(lib, handle, sampleRate, frame);
  }

  final DynamicLibrary _lib;
  final Pointer<Void> _handle;
  final int sampleRate;
  final int frame;
  final Pointer<Int16> _io;
  bool _disposed = false;

  late final _StartD _start =
      _lib.lookupFunction<_StartC, _StartD>('aec_engine_start');
  late final _StartD _startNull =
      _lib.lookupFunction<_StartC, _StartD>('aec_engine_start_null');
  late final _StartNamedD _startNamed =
      _lib.lookupFunction<_StartNamedC, _StartNamedD>('aec_engine_start_named');
  late final _RefPumpD _reference =
      _lib.lookupFunction<_RefPumpC, _RefPumpD>('aec_engine_reference');
  late final _RefPumpD _pump =
      _lib.lookupFunction<_RefPumpC, _RefPumpD>('aec_engine_test_pump');
  late final _ReadD _read =
      _lib.lookupFunction<_ReadC, _ReadD>('aec_engine_read');
  late final _ReadD _readRaw =
      _lib.lookupFunction<_ReadC, _ReadD>('aec_engine_read_raw');
  late final _SetPeriodD _setPeriod =
      _lib.lookupFunction<_SetPeriodC, _SetPeriodD>('aec_engine_set_period');
  late final _SetPeriodD _setDtd =
      _lib.lookupFunction<_SetPeriodC, _SetPeriodD>('aec_engine_set_dtd');
  late final _StopD _stop =
      _lib.lookupFunction<_StopC, _StopD>('aec_engine_stop');
  late final _DestroyD _destroy =
      _lib.lookupFunction<_DestroyC, _DestroyD>('aec_engine_destroy');

  /// Override the device period (frames per callback), decoupling it from the
  /// AEC block size. Call before starting. Keeps device latency (and thus the
  /// acoustic round-trip delay) short while the longer AEC block covers it.
  void setPeriod(int period) => _setPeriod(_handle, period);

  /// Enable/disable the double-talk detector (default off). When on, the engine
  /// freezes filter adaptation on near-end-present blocks, so the user's own
  /// playing/singing survives with far less residual echo.
  void setDtd(bool enabled) => _setDtd(_handle, enabled ? 1 : 0);

  /// Start on the system default duplex device. Returns 0 on success.
  int start() => _start(_handle);

  /// Start on the miniaudio null backend (headless lifecycle test).
  int startNull() => _startNull(_handle);

  /// Start on named playback/capture devices (substring match); null = default.
  int startNamed({String? playback, String? capture}) {
    final p = playback == null ? nullptr : playback.toNativeUtf8();
    final c = capture == null ? nullptr : capture.toNativeUtf8();
    try {
      return _startNamed(_handle, p, c);
    } finally {
      if (p != nullptr) calloc.free(p);
      if (c != nullptr) calloc.free(c);
    }
  }

  /// Queue reference PCM16 to be played AND cancelled.
  void reference(Int16List pcm) => _writeThen(pcm, _reference);

  /// TEST: run `mic` PCM16 through the exact callback processing (no device).
  void pump(Int16List mic) => _writeThen(mic, _pump);

  void _writeThen(Int16List data, _RefPumpD fn) {
    var offset = 0;
    while (offset < data.length) {
      final n = (data.length - offset).clamp(0, sampleRate);
      _io.asTypedList(n).setAll(0, data.sublist(offset, offset + n));
      fn(_handle, _io, n);
      offset += n;
    }
  }

  /// Drain up to [max] cleaned near-end samples (default: the whole buffer).
  Int16List read({int? max}) => _drain(_read, max);

  /// Drain up to [max] raw (pre-cancellation) mic samples.
  Int16List readRaw({int? max}) => _drain(_readRaw, max);

  Int16List _drain(_ReadD fn, int? max) {
    final out = <int>[];
    final cap = max ?? sampleRate;
    while (true) {
      final want =
          (max == null ? sampleRate : (cap - out.length)).clamp(0, sampleRate);
      if (want == 0) break;
      final n = fn(_handle, _io, want);
      if (n <= 0) break;
      out.addAll(_io.asTypedList(n));
      if (n < want) break; // ring drained
    }
    return Int16List.fromList(out);
  }

  int stop() => _stop(_handle);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
    calloc.free(_io);
  }
}
