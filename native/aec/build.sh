#!/usr/bin/env bash
# build.sh — build the native AEC and run the offline ERLE cross-check.
#
# Wraps the build in the GEM-env fix from the repo CLAUDE.md so a broken system
# Ruby can't interfere with CMake/clang on this Mac. Safe on other machines too
# (env -u just unsets vars that may not be set).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

run() { PATH="/usr/bin:$PATH" env -u GEM_HOME -u GEM_PATH -u RUBYOPT "$@"; }

echo "==> configure + build (Release)"
run cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
run cmake --build build --config Release

# This is a Flutter FFI plugin (depends on the flutter SDK) and its tests import
# package:flutter_test, so use `flutter pub get` / `flutter test`, NOT `dart …`
# (which can't resolve the flutter SDK dep and errors "Could not find package
# test"). The GEM-env wrapper keeps the broken system Ruby out of flutter's way.
echo "==> flutter pub get"
run flutter pub get

# Run the cross-check OUTSIDE the GEM-env wrapper: that wrapper hangs the flutter
# test runner on this Mac (it's only needed for cmake/pod/xcodebuild). Point the
# FFI loader at the FULL library (libaec) — it carries the DSP + DTD symbols the
# aec_erle test needs AND the aec_engine_* symbols the engine test needs.
echo "==> offline ERLE + DTD cross-check"
ext=so; libpref=lib
case "$(uname -s)" in
  Darwin) ext=dylib ;;
  MINGW*|MSYS*|CYGWIN*) ext=dll; libpref="" ;;
esac
AEC_LIBRARY_PATH="$HERE/build/${libpref}aec.$ext" flutter test
