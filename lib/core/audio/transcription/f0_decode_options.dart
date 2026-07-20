// A process-wide override for the neural F0 decoders' Viterbi path-smoothing,
// so the feature is reachable from BOTH the CLI (`--f0-viterbi`) and the app
// (a Settings toggle) without threading a flag through the whole engine-resolve
// stack. The per-model `COMET_{CREPE,RMVPE,FCPE}_VITERBI` env gates stay the
// fallback when nothing overrides them.
//
// Web-safe: no `dart:io` — the env map is passed in by the (native-only) model
// stores, so the app's config service can set [viterbi] on any platform.

class F0DecodeOptions {
  F0DecodeOptions._();

  /// Force Viterbi on/off for every neural F0 decoder. `null` (the default)
  /// defers to each model's `COMET_*_VITERBI` env gate; `true`/`false` wins over
  /// it. Set by the `--f0-viterbi` CLI flag and the Settings toggle.
  static bool? viterbi;

  /// The effective Viterbi setting for [envKey]: the [viterbi] override when it
  /// is set, otherwise the env gate (`"1"` = on) read from [env].
  static bool resolve(String envKey, Map<String, String> env) =>
      viterbi ?? (env[envKey] == '1');
}
