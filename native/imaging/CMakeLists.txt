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
if(CMAKE_OSX_ARCHITECTURES)
  list(APPEND LJT_ARGS -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES})
endif()
ExternalProject_Add(libjpeg_turbo_external
  SOURCE_DIR ${LJT_SOURCE_DIR}
  INSTALL_DIR ${LJT_INSTALL_DIR}
  CMAKE_GENERATOR ${CMAKE_GENERATOR}
  CMAKE_ARGS ${LJT_ARGS}
  BUILD_BYPRODUCTS ${LJT_LIBRARY})
file(MAKE_DIRECTORY ${LJT_INSTALL_DIR}/include)
add_library(gremote_jpeg STATIC IMPORTED)
set_target_properties(gremote_jpeg PROPERTIES
  IMPORTED_LOCATION ${LJT_LIBRARY}
  INTERFACE_INCLUDE_DIRECTORIES ${LJT_INSTALL_DIR}/include)
add_dependencies(gremote_jpeg libjpeg_turbo_external)

set(GREMOTE_CORE_SOURCES
  src/cube_lut.cpp
  src/orientation.cpp
  src/resize.cpp
  src/jpeg_io.cpp
  src/frame_compositor.cpp
  src/api.cpp)

add_library(gremote_core OBJECT ${GREMOTE_CORE_SOURCES})
target_include_directories(gremote_core PUBLIC include src)
target_link_libraries(gremote_core PUBLIC gremote_jpeg)
find_package(Threads REQUIRED)
target_link_libraries(gremote_core PUBLIC Threads::Threads)

add_library(gremote_imaging SHARED)
target_link_libraries(gremote_imaging PRIVATE gremote_core)
if(ANDROID)
  target_link_options(gremote_imaging PRIVATE -Wl,-z,max-page-size=16384)
endif()

if(NOT ANDROID)
  enable_testing()
  add_executable(gremote_imaging_tests
    tests/test_runner.cpp
    tests/cube_lut_test.cpp
    tests/orientation_resize_test.cpp
    tests/jpeg_io_test.cpp
    tests/compositor_api_test.cpp)
  target_link_libraries(gremote_imaging_tests PRIVATE gremote_core)
  add_test(NAME gremote_imaging_tests COMMAND gremote_imaging_tests)
endif()
