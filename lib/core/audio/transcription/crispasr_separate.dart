// Facade for the CrispASR-CLI source separator (native only, behind a
// conditional import so a web build still compiles). The IO impl shells out to
// the CrispASR `--separate` command (ggml HTDemucs / mel-band-roformer, MIT —
// fully parity + fast as of §248); the stub returns null (web / no binary), so
// transcribeSong falls back to a single part.
//
// SWAP TARGET (crispasr 0.8.17+): the shell-out becomes an in-app FFI call —
// `CrispasrSession.separate(Float32List) → List<Stem>` where
// `Stem = ({String name, Float32List pcm})`, with a `separateSampleRate` probe.
// Contract: input is INTERLEAVED STEREO at 44.1 kHz; the native side counts
// samples per channel, so an odd-length buffer throws. Wire a crispasr_ffi_
// separate.dart provider (mirroring crispasr_ffi_pitch.dart) once 0.8.17 is on
// pub.dev, and prefer it over this CLI path — then drop the Open-Unmix effort.

export 'crispasr_separate_stub.dart'
    if (dart.library.io) 'crispasr_separate_io.dart';
