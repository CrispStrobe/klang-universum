# MP3 port — glint comparison harness

Validates the pure-Dart MP3 encoder DSP (`lib/core/audio/mp3/`) against glint's
C++ reference (`~/code/glint`, MIT clean-room), for **bit-exactness** and
**speed**. `bench/glint_ref.cpp` and `bin/mp3_bench.dart` feed the SAME
deterministic LCG input through the subband filter + MDCT + alias reduction.

## Reproduce
```bash
# 1. build glint (once)
cmake -S ~/code/glint -B /tmp/glint -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/glint --target glint_static

# 2. C++ reference + benchmark (dumps ref.txt, prints granules/s to stderr)
c++ -O3 -std=c++17 -march=native bench/glint_ref.cpp \
    -I ~/code/glint/src -I ~/code/glint/include /tmp/glint/libglint.a -o /tmp/glint_ref
/tmp/glint_ref 20000 /tmp/ref.txt

# 3. Dart: compare to the reference + benchmark
dart run bin/mp3_bench.dart /tmp/ref.txt 20000
```

## Results (2026-07-18, Apple Silicon)
- **Accuracy — machine-equivalent.** subband max abs err **5.3e-15**, MDCT
  **6.7e-16** (signal peak ~11.5 → **relative ~5e-16**, the double-precision
  floor). `acc` matches glint exactly. NOT literally bit-identical only because
  glint builds with `-ffast-math`/FMA (reassociates float ops); the Dart port
  is strict IEEE double. `test/mp3_golden_test.dart` pins glint's dumped values
  in CI (no glint needed).
- **Speed.** glint C++ (`-O3 -march=native`) ≈ **95,640 granules/s**; Dart JIT
  (`dart run`) ≈ **4,000 granules/s** → **~24× slower**. A granule is 576
  samples = **13 ms of audio**, so even JIT is **~52× realtime**; release
  builds are AOT (faster). Encoding a 3-min song ≈ 13,850 granules ≈ 3.5 s JIT.
  (AOT `dart compile exe` is blocked here by the app's native-asset deps, so
  the in-app release-mode number will sit between JIT and glint.)
