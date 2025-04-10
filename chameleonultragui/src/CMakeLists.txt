# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)
if (CMAKE_VERSION VERSION_GREATER_EQUAL "3.24.0")
  cmake_policy(SET CMP0135 NEW)
endif()

project(recovery_library VERSION 0.0.1 LANGUAGES C)

set(COMMON_FILES
    ${SRC_DIR}/crapto1.c
    ${SRC_DIR}/crypto1.c
    ${SRC_DIR}/bucketsort.c
    ${SRC_DIR}/mfkey.c
    ${SRC_DIR}/parity.c
    ${SRC_DIR}/hardnested.c
    ${SRC_DIR}/pm3/commonutil.c
    ${SRC_DIR}/pm3/ui.c
    ${SRC_DIR}/pm3/util_posix.c
    ${SRC_DIR}/pm3/util.c
    ${SRC_DIR}/hardnested/tables.c
    ${SRC_DIR}/hardnested/hardnested_bruteforce.c
    ${SRC_DIR}/hardnested/hardnested_bitarray_core.c
    ${SRC_DIR}/hardnested/hardnested_bf_core.c
)

include_directories(${SRC_DIR}/)

add_library(recovery SHARED
  "recovery.c"
  "crapto1.c"
  "crypto1.c"
  "bucketsort.c"
  "mfkey.c"
  "parity.c"
  "hardnested.c"
  "pm3/commonutil.c"
  "pm3/ui.c"
  "pm3/util_posix.c"
  "pm3/util.c"
  "hardnested/tables.c"
  "hardnested/hardnested_bruteforce.c"
  "hardnested/hardnested_bitarray_core.c"
  "hardnested/hardnested_bf_core.c"
)

add_compile_options(-O3 -Ofast)

set_target_properties(recovery PROPERTIES
  PUBLIC_HEADER recovery.h
  OUTPUT_NAME "recovery"
)

target_compile_definitions(recovery PUBLIC DART_SHARED_LIB)

if (WIN32)
  # Workaround Flutter bug for Windows
  set_target_properties(recovery PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS ON
  )

  add_custom_command(
    TARGET recovery POST_BUILD
    COMMAND ../../../src/post_build.bat $<CONFIG> $<TARGET_FILE_DIR:recovery>
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  )
endif (WIN32)

include(ExternalProject)

set(XZ_INSTALL_DIR ${CMAKE_BINARY_DIR}/xz_utils_install)

file(MAKE_DIRECTORY ${XZ_INSTALL_DIR}/include)
file(MAKE_DIRECTORY ${XZ_INSTALL_DIR}/lib)

set(XZ_CMAKE_ARGS
  -DCMAKE_INSTALL_PREFIX=${XZ_INSTALL_DIR}
  -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
  -DBUILD_SHARED_LIBS=OFF
)

if(ANDROID)
  list(APPEND XZ_CMAKE_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DANDROID_NDK=${ANDROID_NDK}
    -DCMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
    -DCMAKE_SYSTEM_VERSION=${CMAKE_SYSTEM_VERSION}
  )
elseif(UNIX AND NOT APPLE)
  list(APPEND XZ_CMAKE_ARGS
    -DCMAKE_C_FLAGS="-fPIC"
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  )
endif()

ExternalProject_Add(
  xz_utils
  URL https://tukaani.org/xz/xz-5.8.1.tar.gz
  URL_HASH SHA256=507825b599356c10dca1cd720c9d0d0c9d5400b9de300af00e4d1ea150795543
  CMAKE_ARGS ${XZ_CMAKE_ARGS}
  BUILD_BYPRODUCTS ${XZ_INSTALL_DIR}/lib/liblzma.a
)

set(LZMA_INCLUDE_DIR ${XZ_INSTALL_DIR}/include)
set(LZMA_LIBRARY ${XZ_INSTALL_DIR}/lib/liblzma.a)

add_library(lzma STATIC IMPORTED)
set_target_properties(lzma PROPERTIES
  IMPORTED_LOCATION ${LZMA_LIBRARY}
  INTERFACE_INCLUDE_DIRECTORIES ${LZMA_INCLUDE_DIR}
)

add_dependencies(lzma xz_utils)
target_link_libraries(recovery PUBLIC lzma)