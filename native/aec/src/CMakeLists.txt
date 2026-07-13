# src/CMakeLists.txt — the SHARED native build used by the Flutter FFI plugin on
# Android, Linux and Windows (Apple platforms compile the same sources via the
# podspecs + Classes/ forwarders instead). Builds one library, `aec_fullduplex`,
# containing the MIT AEC core + the miniaudio duplex host.
#
# This is the plugin build. The standalone dev/CI build lives in the package's
# top-level CMakeLists.txt (which produces libaec/libaec_dsp for the offline
# tests) — the two are independent on purpose.
cmake_minimum_required(VERSION 3.10)

project(aec_fullduplex_library VERSION 0.1.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# MSVC exports nothing from a DLL without this; harmless elsewhere.
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

add_library(aec_fullduplex SHARED
  aec_dsp.c
  aec_shim.c
  miniaudio_impl.c
)

set_target_properties(aec_fullduplex PROPERTIES
  PUBLIC_HEADER "aec_shim.h;aec_dsp.h"
  OUTPUT_NAME "aec_fullduplex"
)

# The Dart side keys off this to pick the right DynamicLibrary name.
target_compile_definitions(aec_fullduplex PUBLIC DART_SHARED_LIB)

if(ANDROID)
  target_link_libraries(aec_fullduplex PRIVATE OpenSLES log)
  # Support Android 15 16k page size.
  target_link_options(aec_fullduplex PRIVATE "-Wl,-z,max-page-size=16384")
elseif(UNIX AND NOT APPLE)
  find_library(PTHREAD_LIB pthread)
  target_link_libraries(aec_fullduplex PRIVATE ${CMAKE_DL_LIBS} m pthread)
endif()
# Apple links CoreAudio/AudioToolbox/AudioUnit via the podspec frameworks.
