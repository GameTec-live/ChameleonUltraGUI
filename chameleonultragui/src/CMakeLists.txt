# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(recovery_library VERSION 0.0.1 LANGUAGES C)

set(COMMON_FILES
    ${SRC_DIR}/crapto1.c
    ${SRC_DIR}/crypto1.c
    ${SRC_DIR}/bucketsort.c
    ${SRC_DIR}/mfkey.c
    ${SRC_DIR}/parity.c
    ${SRC_DIR}/hardnested/cmdhfmfhard.c
    ${SRC_DIR}/hardnested/pm3/commonutil.c
    ${SRC_DIR}/hardnested/pm3/ui.c
    ${SRC_DIR}/hardnested/pm3/util_posix.c
    ${SRC_DIR}/hardnested/pm3/util.c
    ${SRC_DIR}/hardnested/hardnested/tables.c
    ${SRC_DIR}/hardnested/hardnested/hardnested_bruteforce.c
    ${SRC_DIR}/hardnested/hardnested/hardnested_bitarray_core.c
    ${SRC_DIR}/hardnested/hardnested/hardnested_bf_core.c
    )

include_directories(
    ${SRC_DIR}/
    )

add_library(recovery SHARED
  "recovery.c"
  "crapto1.c"
  "crypto1.c"
  "bucketsort.c"
  "mfkey.c"
  "parity.c"
  "hardnested/pm3/commonutil.c"
  "hardnested/pm3/ui.c"
  "hardnested/pm3/util_posix.c"
  "hardnested/pm3/util.c"
  "hardnested/hardnested/tables.c"
  "hardnested/hardnested/hardnested_bruteforce.c"
  "hardnested/hardnested/hardnested_bitarray_core.c"
  "hardnested/hardnested/hardnested_bf_core.c"
)

add_compile_options(-O3 -Ofast)

set_target_properties(recovery PROPERTIES
  PUBLIC_HEADER recovery.h
  OUTPUT_NAME "recovery"
)

target_compile_definitions(recovery PUBLIC DART_SHARED_LIB)

if (WIN32)
  # Workaround Flutter bug
  set_target_properties(recovery PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS ON
  )

  add_custom_command(
    TARGET recovery POST_BUILD
    COMMAND ../../../src/post_build.bat $<CONFIG> $<TARGET_FILE_DIR:recovery>
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  )
endif (WIN32)
