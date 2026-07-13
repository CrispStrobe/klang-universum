# Flutter FFI plugin (Windows) — delegates to the shared native build under ../src.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "aec_fullduplex")
project(${PROJECT_NAME} LANGUAGES C)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src"
                 "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(aec_fullduplex_bundled_libraries
  $<TARGET_FILE:aec_fullduplex>
  PARENT_SCOPE
)
