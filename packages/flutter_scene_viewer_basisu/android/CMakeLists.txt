cmake_minimum_required(VERSION 3.12)

project(flutter_scene_viewer_basisu LANGUAGES C CXX)

add_library(
  flutter_scene_viewer_basisu
  SHARED
  src/main/cpp/flutter_scene_viewer_basisu_jni.cc
  src/main/cpp/fsv_basisu_budget.cc
  src/main/cpp/fsv_basisu_control.cc
  src/main/cpp/fsv_basisu_bridge.cc
  ../third_party/basis_universal/transcoder/basisu_transcoder.cpp
  ../third_party/basis_universal/zstd/zstddeclib.c
)

target_compile_features(flutter_scene_viewer_basisu PRIVATE cxx_std_17)
target_compile_definitions(
  flutter_scene_viewer_basisu
  PRIVATE
  BASISD_SUPPORT_KTX2=1
  BASISD_SUPPORT_KTX2_ZSTD=1
)
target_include_directories(
  flutter_scene_viewer_basisu
  PRIVATE
  src/main/cpp
  ../third_party/basis_universal/transcoder
  ../third_party/basis_universal/zstd
)
