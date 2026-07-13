# CMakeLists.txt — builds the native AEC.
#
# Two libraries on purpose:
#   * aec_dsp  — the pure MIT echo-canceller (aec_dsp.c) with ZERO platform
#     dependencies. This is what the offline ERLE cross-check loads; it must
#     compile and run identically everywhere.
#   * aec      — the full plugin: DSP + the miniaudio duplex host (aec_shim.c +
#     miniaudio_impl.c). Links the platform audio frameworks. This is what a
#     Flutter FFI plugin embeds once the per-platform wrappers land (milestone d).
#
# Standalone by design — NOT referenced by the app's pubspec.yaml, so CI never
# compiles it (AEC_TIER3B.md CI-safety rule). Build it explicitly:
#   cmake -S . -B build && cmake --build build

cmake_minimum_required(VERSION 3.15)
project(aec C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# On MSVC a DLL exports nothing unless symbols are marked __declspec(dllexport);
# auto-export everything so the FFI lookups resolve (harmless elsewhere).
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

# --- pure DSP core (portable, offline-testable) ------------------------------
add_library(aec_dsp SHARED src/aec_dsp.c)
target_include_directories(aec_dsp PUBLIC src)
if(NOT MSVC)
  target_link_libraries(aec_dsp PRIVATE m)
endif()

# --- full plugin: DSP + miniaudio duplex host --------------------------------
add_library(aec SHARED src/aec_dsp.c src/aec_shim.c src/miniaudio_impl.c)
target_include_directories(aec PUBLIC src)

if(APPLE)
  target_link_libraries(aec PRIVATE
    "-framework CoreFoundation"
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework AudioUnit")
elseif(ANDROID)
  target_link_libraries(aec PRIVATE OpenSLES log)
elseif(UNIX)
  find_library(PTHREAD pthread)
  target_link_libraries(aec PRIVATE ${CMAKE_DL_LIBS} m pthread)
endif()

if(NOT MSVC AND NOT APPLE)
  target_link_libraries(aec PRIVATE m)
endif()
