cmake_minimum_required(VERSION 3.12)

project(flutter_scene_viewer_draco LANGUAGES CXX)

set(FSV_DRACO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/draco")
set(FSV_DRACO_SRC "${FSV_DRACO_ROOT}/src")

file(
  GLOB_RECURSE
  FSV_DRACO_DECODER_SOURCES
  CONFIGURE_DEPENDS
  "${FSV_DRACO_SRC}/draco/attributes/*.cc"
  "${FSV_DRACO_SRC}/draco/compression/*.cc"
  "${FSV_DRACO_SRC}/draco/core/*.cc"
  "${FSV_DRACO_SRC}/draco/mesh/*.cc"
  "${FSV_DRACO_SRC}/draco/metadata/*.cc"
  "${FSV_DRACO_SRC}/draco/point_cloud/*.cc"
)
list(FILTER FSV_DRACO_DECODER_SOURCES EXCLUDE REGEX ".*_test\\.cc$")
list(FILTER FSV_DRACO_DECODER_SOURCES EXCLUDE REGEX ".*/draco_test_utils\\.cc$")

add_library(fsv_draco_decoder STATIC ${FSV_DRACO_DECODER_SOURCES})
target_compile_features(fsv_draco_decoder PUBLIC cxx_std_17)
target_include_directories(fsv_draco_decoder PUBLIC "${FSV_DRACO_SRC}")

add_library(
  flutter_scene_viewer_draco
  SHARED
  src/main/cpp/flutter_scene_viewer_draco_jni.cc
  src/main/cpp/fsv_draco_budget.cc
  src/main/cpp/fsv_draco_bridge.cc
)

target_compile_features(flutter_scene_viewer_draco PRIVATE cxx_std_17)
target_link_libraries(flutter_scene_viewer_draco PRIVATE fsv_draco_decoder)
