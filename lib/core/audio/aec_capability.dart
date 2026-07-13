// lib/core/audio/aec_capability.dart
//
// The runtime capability check for AEC Tier 3b. [createNativeAecEngine] returns
// a native full-duplex [AecEngine] when the platform supports it, or null to
// fall back to the ordinary `record` capture path (AEC tiers 0/1).
//
// Web-safety: the native implementation pulls in `dart:ffi` (via the
// `aec_fullduplex` plugin), which does NOT exist on the web. The conditional
// export below compiles the ffi-backed factory ONLY where `dart:ffi` is
// available and a `dart:ffi`-free stub everywhere else — so `flutter build web`
// (the deploy path) never sees `dart:ffi`.

export 'aec_capability_stub.dart'
    if (dart.library.ffi) 'aec_capability_ffi.dart';
