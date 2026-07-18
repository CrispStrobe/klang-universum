#!/usr/bin/env python3
"""A/B the pure-Dart MP3 encoder against glint, using glint's OWN harness.

Reuses glint/tests/benchmark_encoder.py's deterministic speech-like signal and
glint/tests/measure_audio.py's objective quality metrics, so the Dart encoder
is judged on exactly the same reference and yardstick as glint itself.

Both encoders run MONO (the Dart first-cut is mono-only) at the same bitrate.
Reports: encode speed each, output size each, and measure_audio's fidelity
table (glint.mp3 vs dart.mp3 vs the original).

    python bench/ab_vs_glint.py [--glint ~/code/glint] [-b 128] [--seconds 30]
"""
import argparse
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100


def mono_speech_wav(path, seconds):
    """glint benchmark_encoder.generate_stereo_wav, mono-mixed (seed 7)."""
    rng = np.random.default_rng(7)
    t = np.arange(SR * seconds) / SR
    env = (0.35 + 0.65 * (0.5 + 0.5 * np.sin(2 * np.pi * 2.7 * t)) *
           (0.7 + 0.3 * np.sin(2 * np.pi * 5.3 * t + 0.4)))
    voiced = sum((1.0 / (i + 1)) *
                 np.sin(2 * np.pi * (155 * (i + 1)) * t + i * 0.37)
                 for i in range(12))
    noise = np.convolve(rng.normal(0, 1, len(t)), np.ones(9) / 9, mode="same")
    sig = (voiced * 0.12 + noise * 0.035) * env
    sig += 0.018 * np.sin(2 * np.pi * 4200 * t) * (
        0.5 + 0.5 * np.sin(2 * np.pi * 3.1 * t))
    sig = np.clip(sig / np.max(np.abs(sig)) * 0.82, -1, 1)
    pcm = (sig * 32767).astype(np.int16)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def speed_of(stderr):
    for line in stderr.splitlines():
        if line.startswith("Speed:"):
            return line.split("Speed:")[1].strip()
    return "?"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--glint", default=os.path.expanduser("~/code/glint"))
    ap.add_argument("-b", "--bitrate", type=int, default=128)
    ap.add_argument("--seconds", type=int, default=30)
    args = ap.parse_args()

    glint_cli = os.path.join(args.glint, "build-bench", "glint_cli")
    if not os.path.isfile(glint_cli):
        glint_cli = os.path.join(args.glint, "build", "glint_cli")
    measure = os.path.join(args.glint, "tests", "measure_audio.py")
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "ref.wav")
        gmp3 = os.path.join(td, "glint.mp3")
        dmp3 = os.path.join(td, "dart.mp3")
        mono_speech_wav(wav, args.seconds)
        b = str(args.bitrate)

        print(f"=== Encode ({args.seconds}s mono @ {b}k) ===", flush=True)
        g = subprocess.run([glint_cli, wav, gmp3, "-b", b, "-m", "mono",
                            "-q", "best"], capture_output=True, text=True,
                           check=True)
        print(f"  glint : {speed_of(g.stderr):<40} {os.path.getsize(gmp3)} B")

        d = subprocess.run(["dart", "run", "bin/mp3_encode_cli.dart", wav,
                            dmp3, "-b", b], capture_output=True, text=True,
                           cwd=repo)
        if d.returncode != 0:
            print(d.stdout, d.stderr, file=sys.stderr)
            return 1
        print(f"  dart  : {speed_of(d.stderr):<40} {os.path.getsize(dmp3)} B")

        # ffmpeg sanity: both must decode cleanly.
        for name, mp3 in [("glint", gmp3), ("dart", dmp3)]:
            r = subprocess.run(["ffmpeg", "-v", "error", "-i", mp3, "-f",
                                "null", "-"], capture_output=True, text=True)
            print(f"  {name} decode: {'OK' if r.returncode == 0 else r.stderr}")

        print("\n=== Objective Quality (glint's measure_audio.py) ===",
              flush=True)
        subprocess.run([sys.executable, measure, wav, gmp3, dmp3], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
