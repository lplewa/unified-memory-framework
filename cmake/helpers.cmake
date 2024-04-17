# Copyright (C) 2023-2024 Intel Corporation
# Under the Apache License v2.0 with LLVM Exceptions. See LICENSE.TXT.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#
# helpers.cmake -- helper functions for top-level CMakeLists.txt
#

# CMake modules that check whether the C/C++ compiler supports a given flag
include(CheckCCompilerFlag)
include(CheckCXXCompilerFlag)

# Sets ${ret} to version of program specified by ${name} in major.minor format
function(get_program_version_major_minor name ret)
    execute_process(
        COMMAND ${name} --version
        OUTPUT_VARIABLE cmd_ret
        ERROR_QUIET)
    string(REGEX MATCH "([0-9]+)\.([0-9]+)" VERSION "${cmd_ret}")
    set(${ret}
        ${VERSION}
        PARENT_SCOPE)
endfunction()

function(add_umf_target_compile_options name)
    if(NOT MSVC)
        target_compile_options(
            ${name}
            PRIVATE -fPIC
                    -Wall
                    -Wsign-compare
                    -Wconversion
                    -Wpedantic
                    -Wempty-body
                    -Wunused-parameter
                    $<$<CXX_COMPILER_ID:GNU>:-fdiagnostics-color=auto>)
        if(CMAKE_BUILD_TYPE STREQUAL "Release")
            target_compile_definitions(${name} PRIVATE -D_FORTIFY_SOURCE=2)
        endif()
        if(UMF_DEVELOPER_MODE)
            target_compile_options(
                ${name} PRIVATE -Werror -fno-omit-frame-pointer
                                -fstack-protector-strong)
        endif()
    elseif(MSVC)
        target_compile_options(
            ${name}
            PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/MP> # clang-cl.exe does not
                                                   # support /MP
                    /W3 /MD$<$<CONFIG:Debug>:d> /GS)

        if(UMF_DEVELOPER_MODE)
            target_compile_options(${name} PRIVATE /WX /GS)
        endif()
    endif()
endfunction()

function(add_umf_target_link_options name)
    if(NOT MSVC)
        if(NOT APPLE)
            target_link_options(${name} PRIVATE "LINKER:-z,relro,-z,now")
        endif()
    elseif(MSVC)
        target_link_options(
            ${name}
            PRIVATE
            /DYNAMICBASE
            /HIGHENTROPYVA
            /NXCOMPAT)
    endif()
endfunction()

function(add_umf_target_exec_options name)
    if(MSVC)
        target_link_options(${name} PRIVATE /ALLOWISOLATION)
    endif()
endfunction()

function(add_umf_executable)
    # Parameters:
    #
    # * NAME - a name of the executable
    # * SRCS - source files
    # * LIBS - libraries to be linked with
    set(oneValueArgs NAME)
    set(multiValueArgs SRCS LIBS)
    cmake_parse_arguments(
        ARG
        ""
        "${oneValueArgs}"
        "${multiValueArgs}"
        ${ARGN})

    add_executable(${ARG_NAME} ${ARG_SRCS})
    target_link_libraries(${ARG_NAME} PRIVATE ${ARG_LIBS})
    add_umf_target_compile_options(${ARG_NAME})
    add_umf_target_exec_options(${ARG_NAME})
    add_umf_target_link_options(${ARG_NAME})
endfunction()

function(add_umf_library)
    # Parameters:
    #
    # * NAME - a name of the library
    # * TYPE - type of the library (shared or static) if shared library,
    #   LINUX_MAP_FILE and WINDOWS_DEF_FILE must also be specified
    # * SRCS - source files
    # * LIBS - libraries to be linked with
    # * LINUX_MAP_FILE - path to linux linker map (.map) file
    # * WINDOWS_DEF_FILE - path to windows module-definition (DEF) file

    set(oneValueArgs NAME TYPE LINUX_MAP_FILE WINDOWS_DEF_FILE)
    set(multiValueArgs SRCS LIBS)
    cmake_parse_arguments(
        ARG
        ""
        "${oneValueArgs}"
        "${multiValueArgs}"
        ${ARGN})

    add_library(${ARG_NAME} ${ARG_TYPE} ${ARG_SRCS})

    string(TOUPPER "${ARG_TYPE}" ARG_TYPE)
    if(ARG_TYPE STREQUAL "SHARED")
        if(NOT ARG_LINUX_MAP_FILE OR NOT ARG_WINDOWS_DEF_FILE)
            message(FATAL_ERROR "LINUX_MAP_FILE or WINDOWS_DEF_FILE "
                                "not specified")
        endif()

        if(WINDOWS)
            target_link_options(${ARG_NAME} PRIVATE
                                /DEF:${ARG_WINDOWS_DEF_FILE})
        elseif(LINUX)
            target_link_options(${ARG_NAME} PRIVATE
                                "-Wl,--version-script=${ARG_LINUX_MAP_FILE}")
        endif()
    endif()

    target_link_libraries(${ARG_NAME} PRIVATE ${ARG_LIBS})

    target_include_directories(
        ${ARG_NAME}
        PRIVATE ${UMF_CMAKE_SOURCE_DIR}/include
                ${UMF_CMAKE_SOURCE_DIR}/src/utils
                ${UMF_CMAKE_SOURCE_DIR}/src/base_alloc)
    add_umf_target_compile_options(${ARG_NAME})
    add_umf_target_link_options(${ARG_NAME})
endfunction()

# Add sanitizer ${flag}, if it is supported, for both C and C++ compiler
macro(add_sanitizer_flag flag)
    set(SANITIZER_FLAG "-fsanitize=${flag}")
    if(NOT MSVC)
        # Not available on MSVC.
        set(SANITIZER_ARGS "-fno-sanitize-recover=all")
    endif()

    # Save current 'SAVED_CMAKE_REQUIRED_FLAGS' state and temporarily extend it
    # with '-fsanitize=${flag}'. It is required by CMake to check the compiler
    # for availability of provided sanitizer ${flag}.
    set(SAVED_CMAKE_REQUIRED_FLAGS ${CMAKE_REQUIRED_FLAGS})
    set(CMAKE_REQUIRED_FLAGS "${CMAKE_REQUIRED_FLAGS} ${SANITIZER_FLAG}")

    if(${flag} STREQUAL "address")
        set(check_name "HAS_ASAN")
    elseif(${flag} STREQUAL "undefined")
        set(check_name "HAS_UBSAN")
    elseif(${flag} STREQUAL "thread")
        set(check_name "HAS_TSAN")
    elseif(${flag} STREQUAL "memory")
        set(check_name "HAS_MSAN")
    endif()

    # Check C and CXX compilers for a given sanitizer flag.
    check_c_compiler_flag("${SANITIZER_FLAG}" "C_${check_name}")
    if(NOT C_${check_name})
        message(FATAL_ERROR "sanitizer '${flag}' is not supported "
                            "by the C compiler)")
    endif()
    if(CMAKE_CXX_COMPILE_FEATURES)
        check_cxx_compiler_flag("${SANITIZER_FLAG}" "CXX_${check_name}")
        if(NOT CXX_${check_name})
            message(FATAL_ERROR "sanitizer '${flag}' is not supported by the "
                                "CXX compiler)")
        endif()
    endif()

    add_compile_options("${SANITIZER_FLAG}")

    # Check C and CXX compilers for sanitizer arguments.
    if(SANITIZER_ARGS)
        check_c_compiler_flag("${SANITIZER_ARGS}" "C_HAS_SAN_ARGS")
        if(NOT C_HAS_SAN_ARGS)
            message(FATAL_ERROR "sanitizer argument '${SANITIZER_ARGS}' is "
                                "not supported by the C compiler)")
        endif()
        if(CMAKE_CXX_COMPILE_FEATURES)
            check_cxx_compiler_flag("${SANITIZER_ARGS}" "CXX_HAS_SAN_ARGS")
            if(NOT CXX_HAS_SAN_ARGS)
                message(FATAL_ERROR "sanitizer argument '${SANITIZER_ARGS}' "
                                    "is not supported by the CXX compiler)")
            endif()
        endif()

        add_compile_options("${SANITIZER_ARGS}")
    endif()

    # Clang/gcc needs the flag added to the linker. The Microsoft LINK linker
    # doesn't recognize sanitizer flags and will give a LNK4044 warning.
    if(NOT MSVC)
        add_link_options("${SANITIZER_FLAG}")
    endif()

    set(CMAKE_REQUIRED_FLAGS ${SAVED_CMAKE_REQUIRED_FLAGS})
endmacro()
