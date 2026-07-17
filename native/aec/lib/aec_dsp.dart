// Low-level Dart binding to the pure MIT echo-canceller (aec_dsp.h).
//
// This is the offline, device-free layer: it exercises exactly the same
// algorithm as lib/core/audio/echo_canceller.dart, so the ERLE cross-check test
// can assert the C port matches the Dart core. Callers manage lifetime with
// [create]/[dispose].

import 'dart:ffi';
import 'dart:typed_data';

import 'package:aec_fullduplex/src/native_library.dart';
import 'package:ffi/ffi.dart';

typedef _CreateDefaultC = Pointer<Void> Function(Int32);
typedef _CreateDefaultD = Pointer<Void> Function(int);
typedef _ProcessC = Void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Pointer<Double>);
typedef _ProcessD = void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Pointer<Double>);
typedef _VoidPtrC = Void Function(Pointer<Void>);
typedef _VoidPtrD = void Function(Pointer<Void>);
typedef _SetAdaptC = Void Function(Pointer<Void>, Int32);
typedef _SetAdaptD = void Function(Pointer<Void>, int);
typedef _DtdCreateDefaultC = Pointer<Void> Function();
typedef _DtdCreateDefaultD = Pointer<Void> Function();
typedef _DtdFreezeC = Int32 Function(Pointer<Void>);
typedef _DtdFreezeD = int Function(Pointer<Void>);
typedef _DtdUpdateC = Void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Pointer<Double>, Int32);
typedef _DtdUpdateD = void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Pointer<Double>, int);
typedef _ResCreateDefaultC = Pointer<Void> Function(Int32);
typedef _ResCreateDefaultD = Pointer<Void> Function(int);
typedef _ResProcessC = Void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Int32, Pointer<Double>);
typedef _ResProcessD = void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, int, Pointer<Double>);

/// A single adaptive-filter instance backed by the native `aec_dsp_*` core.
class AecDsp {
  AecDsp._(this._lib, this._handle, this.blockSize)
      : _ref = calloc<Double>(blockSize),
        _mic = calloc<Double>(blockSize),
        _out = calloc<Double>(blockSize);

  /// Open the native library (see [openAecLibrary]) and create a canceller with
  /// the Dart `EchoCanceller` defaults for [blockSize] (a power of two).
  factory AecDsp.create({int blockSize = 1024, String? libraryPath}) {
    final lib = openAecLibrary(libraryPath);
    final create = lib.lookupFunction<_CreateDefaultC, _CreateDefaultD>(
        'aec_dsp_create_default');
    final handle = create(blockSize);
    if (handle == nullptr) {
      throw StateError('aec_dsp_create_default($blockSize) returned null '
          '(blockSize must be a power of two)');
    }
    return AecDsp._(lib, handle, blockSize);
  }

  final DynamicLibrary _lib;
  final Pointer<Void> _handle;
  final int blockSize;
  final Pointer<Double> _ref;
  final Pointer<Double> _mic;
  final Pointer<Double> _out;
  bool _disposed = false;

  late final _ProcessD _process =
      _lib.lookupFunction<_ProcessC, _ProcessD>('aec_dsp_process');
  late final _VoidPtrD _reset =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_dsp_reset');
  late final _VoidPtrD _destroy =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_dsp_destroy');
  late final _SetAdaptD _setAdapt =
      _lib.lookupFunction<_SetAdaptC, _SetAdaptD>('aec_dsp_set_adapt');

  /// Gate the NLMS update: false freezes the filter for subsequent blocks
  /// (cancels with the current coefficients, doesn't learn) — driven by a
  /// [AecDtd] to protect the filter during double-talk.
  void setAdapt(bool adapt) => _setAdapt(_handle, adapt ? 1 : 0);

  /// The library handle, so an [AecDtd] can share the same loaded native lib.
  DynamicLibrary get library => _lib;

  /// Cancel the echo of [reference] from [mic] (both [blockSize] long,
  /// time-aligned). Returns the near-end estimate (a fresh [Float64List]).
  Float64List process(Float64List reference, Float64List mic) {
    assert(reference.length == blockSize && mic.length == blockSize);
    final rv = _ref.asTypedList(blockSize);
    final mv = _mic.asTypedList(blockSize);
    rv.setAll(0, reference);
    mv.setAll(0, mic);
    _process(_handle, _ref, _mic, _out);
    return Float64List.fromList(_out.asTypedList(blockSize));
  }

  void reset() => _reset(_handle);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
    calloc.free(_ref);
    calloc.free(_mic);
    calloc.free(_out);
  }
}

/// The native double-talk detector (`aec_dtd_*`) — decides, per block, whether
/// the filter should freeze because near-end speech is present. Pair it with an
/// [AecDsp]: read [freeze] before processing a block (feed to [AecDsp.setAdapt]),
/// then call [update] with that block's reference, mic and cleaned output.
class AecDtd {
  AecDtd._(this._lib, this._handle, this._blockSize)
      : _ref = calloc<Double>(_blockSize),
        _mic = calloc<Double>(_blockSize),
        _cleaned = calloc<Double>(_blockSize);

  /// Create a detector with the Dart `DoubleTalkDetector` defaults, sharing
  /// [aec]'s loaded native library.
  factory AecDtd.createFor(AecDsp aec) {
    final lib = aec.library;
    final create = lib.lookupFunction<_DtdCreateDefaultC, _DtdCreateDefaultD>(
        'aec_dtd_create_default');
    final handle = create();
    if (handle == nullptr) {
      throw StateError('aec_dtd_create_default returned null');
    }
    return AecDtd._(lib, handle, aec.blockSize);
  }

  final DynamicLibrary _lib;
  final Pointer<Void> _handle;
  final int _blockSize;
  final Pointer<Double> _ref;
  final Pointer<Double> _mic;
  final Pointer<Double> _cleaned;
  bool _disposed = false;

  late final _DtdFreezeD _freeze =
      _lib.lookupFunction<_DtdFreezeC, _DtdFreezeD>('aec_dtd_freeze');
  late final _DtdUpdateD _update =
      _lib.lookupFunction<_DtdUpdateC, _DtdUpdateD>('aec_dtd_update');
  late final _VoidPtrD _reset =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_dtd_reset');
  late final _VoidPtrD _destroy =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_dtd_destroy');

  /// Whether the next block should freeze adaptation.
  bool get freeze => _freeze(_handle) != 0;

  /// Update the freeze state from a just-processed block.
  void update(Float64List reference, Float64List mic, Float64List cleaned) {
    _ref.asTypedList(_blockSize).setAll(0, reference);
    _mic.asTypedList(_blockSize).setAll(0, mic);
    _cleaned.asTypedList(_blockSize).setAll(0, cleaned);
    _update(_handle, _ref, _mic, _cleaned, _blockSize);
  }

  void reset() => _reset(_handle);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
    calloc.free(_ref);
    calloc.free(_mic);
    calloc.free(_cleaned);
  }
}

/// The native residual echo suppressor (`aec_res_*`) — a Wiener-style spectral
/// post-filter on the linear canceller's residual. Feed it the cleaned block
/// and the canceller's echo estimate (`mic − cleaned`) each block; set
/// [updateLeak] false during double-talk.
class AecRes {
  AecRes._(this._lib, this._handle, this._blockSize)
      : _cleaned = calloc<Double>(_blockSize),
        _echo = calloc<Double>(_blockSize),
        _out = calloc<Double>(_blockSize);

  /// Create a suppressor with the Dart `ResidualEchoSuppressor` defaults,
  /// sharing [aec]'s loaded native library.
  factory AecRes.createFor(AecDsp aec) {
    final lib = aec.library;
    final create = lib.lookupFunction<_ResCreateDefaultC, _ResCreateDefaultD>(
        'aec_res_create_default');
    final handle = create(aec.blockSize);
    if (handle == nullptr) {
      throw StateError(
          'aec_res_create_default(${aec.blockSize}) returned null');
    }
    return AecRes._(lib, handle, aec.blockSize);
  }

  final DynamicLibrary _lib;
  final Pointer<Void> _handle;
  final int _blockSize;
  final Pointer<Double> _cleaned;
  final Pointer<Double> _echo;
  final Pointer<Double> _out;
  bool _disposed = false;

  late final _ResProcessD _process =
      _lib.lookupFunction<_ResProcessC, _ResProcessD>('aec_res_process');
  late final _VoidPtrD _reset =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_res_reset');
  late final _VoidPtrD _destroy =
      _lib.lookupFunction<_VoidPtrC, _VoidPtrD>('aec_res_destroy');

  /// Suppress residual echo in one [cleaned] block given the [echoEst]
  /// (`mic − cleaned`). Returns the suppressed block (a fresh [Float64List]).
  Float64List process(Float64List cleaned, Float64List echoEst,
      {bool updateLeak = true}) {
    _cleaned.asTypedList(_blockSize).setAll(0, cleaned);
    _echo.asTypedList(_blockSize).setAll(0, echoEst);
    _process(_handle, _cleaned, _echo, updateLeak ? 1 : 0, _out);
    return Float64List.fromList(_out.asTypedList(_blockSize));
  }

  void reset() => _reset(_handle);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
    calloc.free(_cleaned);
    calloc.free(_echo);
    calloc.free(_out);
  }
}
