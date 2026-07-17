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

echo "==> offline ERLE cross-check"
run flutter test
