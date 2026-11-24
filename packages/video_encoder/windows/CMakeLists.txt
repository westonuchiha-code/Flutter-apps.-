cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "video_encoder")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "video_encoder_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/video_encoder/video_encoder_plugin_c_api.h"
  "video_encoder_plugin_c_api.cpp"
  "video_encoder_plugin.cpp"
  "video_encoder_plugin.h"
  "mp4_session.cpp"
  "mp4_session.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_compile_definitions(${PLUGIN_NAME} PRIVATE NOMINMAX)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  mf mfplat mfreadwrite mfuuid ole32)

set(video_encoder_bundled_libraries
  ""
  PARENT_SCOPE
)
