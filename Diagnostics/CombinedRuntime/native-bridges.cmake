# Included by project() in the pinned upstream source. Do not create duplicate
# bridge targets when upstream initializes nested projects.
if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR AND NOT TARGET orivyn-bridges)
  set(ORIVYN_APP_ROOT "$ENV{ORIVYN_BRIDGE_ROOT}")
  if(NOT EXISTS "${ORIVYN_APP_ROOT}/Diagnostics/NativeTools/bridge.cpp")
    message(FATAL_ERROR "ORIVYN_BRIDGE_ROOT must identify the reviewed app source")
  endif()
  add_library(orivyn-bridges STATIC
    "${ORIVYN_APP_ROOT}/Diagnostics/NativeTools/bridge.cpp"
    "${ORIVYN_APP_ROOT}/Diagnostics/VisionProof/Bridge/vision_bridge.cpp")
  target_compile_features(orivyn-bridges PRIVATE cxx_std_17)
  target_include_directories(orivyn-bridges PRIVATE
    "${CMAKE_SOURCE_DIR}/include" "${CMAKE_SOURCE_DIR}/common"
    "${CMAKE_SOURCE_DIR}/ggml/include" "${CMAKE_SOURCE_DIR}/vendor"
    "${CMAKE_SOURCE_DIR}/tools/mtmd")
  target_link_libraries(orivyn-bridges PRIVATE llama-common mtmd)
endif()
