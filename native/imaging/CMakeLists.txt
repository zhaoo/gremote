cmake_minimum_required(VERSION 3.22)
project(gremote_imaging C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# libjpeg-turbo forbids add_subdirectory(); build the vendored source as an
# offline external project and link its static library.
include(ExternalProject)
set(LJT_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libjpeg-turbo-3.0.4)
set(LJT_INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/libjpeg-turbo)
set(LJT_LIBRARY ${LJT_INSTALL_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX})
set(LJT_ARGS
  -DCMAKE_INSTALL_PREFIX=${LJT_INSTALL_DIR}
  -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DENABLE_SHARED=OFF
  -DENABLE_STATIC=ON
  -DWITH_TURBOJPEG=OFF
  -DREQUIRE_SIMD=OFF
  # libjpeg-turbo 3.0.x declares an old minimum; CMake 4 needs this opt-in.
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
if(ANDROID)
  list(APPEND LJT_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  list(APPEND LJT_ARGS
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_SYSTEM_PROCESSOR=${CMAKE_OSX_ARCHITECTURES}
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    -DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
    -DWITH_SIMD=OFF)
  # The iOS library does not ship the vendor's command-line executables.
  set(LJT_EXTERNAL_COMMANDS
    BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --config Release --target jpeg-static
    INSTALL_COMMAND ${CMAKE_COMMAND} --install <BINARY_DIR> --config Release --component lib
    COMMAND ${CMAKE_COMMAND} --install <BINARY_DIR> --config Release --component include)
endif()
if(CMAKE_OSX_ARCHITECTURES)
  list(APPEND LJT_ARGS -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES})
endif()
ExternalProject_Add(libjpeg_turbo_external
  SOURCE_DIR ${LJT_SOURCE_DIR}
  INSTALL_DIR ${LJT_INSTALL_DIR}
  CMAKE_GENERATOR ${CMAKE_GENERATOR}
  CMAKE_ARGS ${LJT_ARGS}
  ${LJT_EXTERNAL_COMMANDS}
  BUILD_BYPRODUCTS ${LJT_LIBRARY})
file(MAKE_DIRECTORY ${LJT_INSTALL_DIR}/include)
add_library(gremote_jpeg STATIC IMPORTED)
set_target_properties(gremote_jpeg PROPERTIES
  IMPORTED_LOCATION ${LJT_LIBRARY}
  INTERFACE_INCLUDE_DIRECTORIES ${LJT_INSTALL_DIR}/include)
add_dependencies(gremote_jpeg libjpeg_turbo_external)

add_library(gremote_skcms STATIC ../third_party/skcms/skcms.cc ../third_party/skcms/src/skcms_TransformBaseline.cc)
target_compile_definitions(gremote_skcms PRIVATE SKCMS_DISABLE_HSW SKCMS_DISABLE_SKX)
target_include_directories(gremote_skcms PUBLIC ../third_party/skcms)

set(GREMOTE_CORE_SOURCES
  src/input_color.cpp
  src/cube_lut.cpp
  src/orientation.cpp
  src/resize.cpp
  src/jpeg_io.cpp
  src/generated_jpeg.cpp
  src/frame_compositor.cpp
  src/api.cpp
  src/photo_edits.cpp
  src/tone_v2.cpp)
list(APPEND GREMOTE_CORE_SOURCES
  src/m10v_preview.cpp
  vendor/m10v/m10v_library.c
  vendor/m10v/halation_core.c
  vendor/m10v/film_5207.c
  vendor/m10v/film_harman.c
  vendor/m10v/film_curated.c
  vendor/m10v/film_newstocks.c)

add_library(gremote_core OBJECT ${GREMOTE_CORE_SOURCES})
# Keep the on-device imaging kernels interactive in debug APKs as well. The
# Flutter app remains debuggable; native symbols are retained by the debug build.
if(ANDROID)
  target_compile_options(gremote_core PRIVATE $<$<CONFIG:Debug>:-O2>)
endif()
target_include_directories(gremote_core PUBLIC include src PRIVATE vendor/m10v)
target_link_libraries(gremote_core PUBLIC gremote_jpeg gremote_skcms)
find_package(Threads REQUIRED)
target_link_libraries(gremote_core PUBLIC Threads::Threads)

add_library(gremote_imaging SHARED)
target_link_libraries(gremote_imaging PRIVATE gremote_core)
if(ANDROID)
  set(GPU_SHADER_HEADER "${CMAKE_CURRENT_BINARY_DIR}/generated/gpu_shaders_generated.h")
  file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")
  file(WRITE "${GPU_SHADER_HEADER}" "#pragma once\nnamespace gremote::gpu::shaders {\n")
  foreach(shader geometry tone lut curves present spatial texture canvas overlay)
    set(shader_file "${CMAKE_CURRENT_SOURCE_DIR}/src/gpu/shaders/${shader}.frag")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${shader_file}")
    file(READ "${shader_file}" shader_source)
    file(APPEND "${GPU_SHADER_HEADER}" "inline constexpr const char* ${shader} = R\"glsl(${shader_source})glsl\";\n")
  endforeach()
  file(APPEND "${GPU_SHADER_HEADER}" "}\n")
  add_library(gremote_gpu OBJECT src/gpu/gpu_context.cpp src/gpu/gpu_source.cpp src/gpu/gpu_session.cpp src/gpu/gpu_pipeline.cpp src/gpu/gpu_effects.cpp src/gpu/gpu_api.cpp src/gpu/gpu_export.cpp)
  target_include_directories(gremote_gpu PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
  target_include_directories(gremote_gpu PUBLIC include src)
  target_link_libraries(gremote_gpu PUBLIC EGL GLESv3 android)
  target_link_libraries(gremote_imaging PRIVATE gremote_gpu)
endif()
if(ANDROID)
  target_link_options(gremote_imaging PRIVATE -Wl,-z,max-page-size=16384)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  target_sources(gremote_imaging PRIVATE src/ios_framework_anchor.cpp)
  set_target_properties(gremote_imaging PROPERTIES
    FRAMEWORK TRUE
    FRAMEWORK_VERSION A
    MACOSX_FRAMEWORK_IDENTIFIER com.izhaoo.gremote.imaging
    MACOSX_FRAMEWORK_BUNDLE_NAME gremote_imaging
    MACOSX_FRAMEWORK_BUNDLE_VERSION 1
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING 1.0.0
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER com.izhaoo.gremote.imaging
    PUBLIC_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/include/gremote_imaging.h"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
endif()

if(NOT ANDROID AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  enable_testing()
  add_executable(gremote_imaging_tests
    tests/test_runner.cpp
    tests/cube_lut_test.cpp
    tests/orientation_resize_test.cpp
    tests/jpeg_io_test.cpp
    tests/compositor_api_test.cpp
    tests/photo_edits_test.cpp
    tests/tone_v2_test.cpp
    tests/gpu_generation_test.cpp
    tests/gpu_pipeline_test.cpp)
  target_sources(gremote_imaging_tests PRIVATE tests/m10v_preview_test.cpp)
  target_link_libraries(gremote_imaging_tests PRIVATE gremote_core)
  add_test(NAME gremote_imaging_tests COMMAND gremote_imaging_tests)
endif()

# Opt-in standalone diagnostic. Normal app builds still compile only the library.
option(GREMOTE_BUILD_GPU_PROBE "Build synthetic Android GPU capability probe" OFF)
if(ANDROID AND GREMOTE_BUILD_GPU_PROBE)
  add_executable(gremote_gpu_probe tests/gpu_capabilities_probe.cpp)
  target_compile_options(gremote_gpu_probe PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(gremote_gpu_probe PRIVATE EGL GLESv3)
  add_executable(gremote_gpu_session_tests tests/gpu_session_device_test.cpp tests/gpu_color_device_test.cpp tests/gpu_effects_device_test.cpp tests/gpu_export_device_test.cpp)
  target_include_directories(gremote_gpu_session_tests PRIVATE tests)
  target_link_libraries(gremote_gpu_session_tests PRIVATE gremote_gpu gremote_core)
endif()
