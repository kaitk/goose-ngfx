# goose-ngfx: graphics for Goose programs on NoGraphicsAPI, beside an
# unmodified Goose (docs/development.md).
#
# Builds the Goose compiler and its gfx, audio and ui layers from the
# third_party/goose submodule, NoGraphicsAPI from third_party/NoGraphicsAPI,
# the native layer that lib/ngfx.goose declares its extern fns against
# (native/), and every sample and test: each Goose program is compiled to C
# by that compiler, then linked with the layer and with Goose's own layers,
# whose SDL3 the ngfx layer shares, so a program has one copy of SDL.

cmake_minimum_required(VERSION 3.24)
project(goose_ngfx C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# The C runtime Goose's archives use (its CMakeLists.txt).
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

# --- Goose ----------------------------------------------------------------------
set(GOOSE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/goose")
foreach(dep IN ITEMS SDL nuklear)
    if(NOT EXISTS "${GOOSE_DIR}/third_party/${dep}/CMakeLists.txt" AND
       NOT EXISTS "${GOOSE_DIR}/third_party/${dep}/nuklear.h")
        message(FATAL_ERROR "No ${GOOSE_DIR}/third_party/${dep}: run "
                            "git submodule update --init --recursive (docs/development.md)")
    endif()
endforeach()
# Programs need no in-process backend or physics; the rest is what they link.
set(GOOSE_LIBTCC OFF CACHE BOOL "" FORCE)
set(GOOSE_PHYSICS OFF CACHE BOOL "" FORCE)
foreach(module IN ITEMS GFX AUDIO UI)
    set(GOOSE_${module} ON CACHE BOOL "" FORCE)
endforeach()
add_subdirectory("${GOOSE_DIR}" "${CMAKE_BINARY_DIR}/goose")
foreach(target IN ITEMS goose_gfx goose_audio goose_ui SDL3::SDL3-static)
    if(NOT TARGET ${target})
        message(FATAL_ERROR "Goose built without ${target}")
    endif()
endforeach()

# --- the shader tools --------------------------------------------------------------
# For the layer's own shaders now, and as the defaults ngfx::slang runs
# later (native/ngfx_slang.cpp), which the environment overrides.
find_program(NGFX_SLANGC NAMES slangc HINTS "${CMAKE_CURRENT_SOURCE_DIR}/../slang/bin"
             DOC "slangc 2026.18.2 or later")
find_program(NGFX_SPIRV_VAL NAMES spirv-val HINTS "$ENV{VULKAN_SDK}/Bin" "$ENV{VULKAN_SDK}/bin"
             DOC "spirv-val, to validate the SPIR-V ngfx::slang makes")
if(NOT NGFX_SLANGC)
    message(FATAL_ERROR "No slangc: set NGFX_SLANGC (docs/development.md)")
endif()

# --- NoGraphicsAPI ------------------------------------------------------------------
# Its CMakeLists needs Metal 4 (macOS 26) on Apple and Vulkan 1.4.357
# elsewhere. It presents on Apple and Windows only.
set(NGFX_NG "${CMAKE_CURRENT_SOURCE_DIR}/third_party/NoGraphicsAPI")
if(NOT EXISTS "${NGFX_NG}/CMakeLists.txt")
    message(FATAL_ERROR "No NoGraphicsAPI: git submodule update --init")
endif()
if(NOT APPLE AND NOT WIN32)
    message(FATAL_ERROR "NoGraphicsAPI is headless-only on ${CMAKE_SYSTEM_NAME}; ngfx needs "
                        "Windows or macOS")
endif()
if(APPLE)
    if(NOT NGFX_METAL_CHECKED)
        execute_process(COMMAND xcrun -sdk macosx metal --version RESULT_VARIABLE metal_result
                        OUTPUT_QUIET ERROR_QUIET)
        if(NOT metal_result EQUAL 0)
            message(FATAL_ERROR "No Metal toolchain (xcodebuild -downloadComponent MetalToolchain)")
        endif()
        set(NGFX_METAL_CHECKED ON CACHE INTERNAL "")
    endif()
else()
    find_package(Vulkan 1.4.357 REQUIRED)
    if(NOT NGFX_SPIRV_VAL)
        message(FATAL_ERROR "No spirv-val (it comes with the Vulkan SDK)")
    endif()
endif()
add_subdirectory("${NGFX_NG}" "${CMAKE_BINARY_DIR}/NoGraphicsAPI" EXCLUDE_FROM_ALL)

set(NGFX_OUT "${CMAKE_BINARY_DIR}/shaders")

# --- the layer's own shaders --------------------------------------------------------
# The screen's copy into the window, and the downsampling generate_mips
# dispatches, each compiled as ngfx::slang compiles a module: every entry
# point at once, NoGraphicsAPI's options, into a header of bytes.
set(ngfx_shader_options -fvk-use-c-layout -matrix-layout-row-major
    -I "${NGFX_NG}/include" -I "${NGFX_NG}/utility/include")
function(ngfx_layer_shader name)
    set(source "${CMAKE_CURRENT_SOURCE_DIR}/native/${name}.slang")
    set(bin "${NGFX_OUT}/${name}.bin")
    if(APPLE)
        add_custom_command(
            OUTPUT "${bin}"
            BYPRODUCTS "${NGFX_OUT}/${name}.metal" "${NGFX_OUT}/${name}.air"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${NGFX_OUT}"
            COMMAND "${NGFX_SLANGC}" "${source}" -target metal -DNOGRAPHICSAPI_METAL ${ngfx_shader_options}
                    -o "${NGFX_OUT}/${name}.metal"
            COMMAND xcrun -sdk macosx metal -std=metal4.0 -c "${NGFX_OUT}/${name}.metal" -o "${NGFX_OUT}/${name}.air"
            COMMAND xcrun -sdk macosx metallib "${NGFX_OUT}/${name}.air" -o "${bin}"
            DEPENDS "${source}" "${NGFX_NG}/include/NoGraphicsAPI/shader.slang"
            VERBATIM
            COMMENT "Compiling ngfx's ${name} to a metallib")
    else()
        add_custom_command(
            OUTPUT "${bin}"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${NGFX_OUT}"
            COMMAND "${NGFX_SLANGC}" "${source}" -target spirv -profile spirv_1_5 -emit-spirv-directly
                    -fvk-use-entrypoint-name ${ngfx_shader_options} -capability spvDescriptorHeapEXT -o "${bin}"
            COMMAND "${NGFX_SPIRV_VAL}" --target-env vulkan1.4 --scalar-block-layout "${bin}"
            DEPENDS "${source}" "${NGFX_NG}/include/NoGraphicsAPI/shader.slang"
            VERBATIM
            COMMENT "Compiling ngfx's ${name} to SPIR-V")
    endif()
    add_custom_command(
        OUTPUT "${NGFX_OUT}/${name}_code.h"
        COMMAND "${CMAKE_COMMAND}" -DINPUT=${bin} -DOUTPUT=${NGFX_OUT}/${name}_code.h
                -DNAME=${name}_code -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/bin2h.cmake"
        DEPENDS "${bin}" "${CMAKE_CURRENT_SOURCE_DIR}/cmake/bin2h.cmake"
        VERBATIM)
endfunction()
ngfx_layer_shader(ngfx_screen)
ngfx_layer_shader(ngfx_mips)

# --- the layer ------------------------------------------------------------------
add_library(ngfx STATIC
    native/ngfx_api.h
    native/ngfx_blob.h
    native/ngfx_internal.h
    native/ngfx_gpu.hpp
    native/ngfx_platform.c
    native/ngfx_device.cpp
    native/ngfx_resources.cpp
    native/ngfx_draw.cpp
    native/ngfx_slang.cpp
    "${NGFX_OUT}/ngfx_screen_code.h"
    "${NGFX_OUT}/ngfx_mips_code.h"
)
target_include_directories(ngfx PRIVATE native "${NGFX_OUT}")
target_link_libraries(ngfx PUBLIC SDL3::SDL3-static NoGraphicsAPI::NoGraphicsAPI NoGraphicsAPIUtility::uploads
                      NoGraphicsAPIUtility::textures NoGraphicsAPIUtility::allocators)
target_compile_definitions(ngfx PRIVATE
    NGFX_SLANGC_PATH="${NGFX_SLANGC}"
    NGFX_NOGRAPHICSAPI_DIR="${NGFX_NG}")
if(NGFX_SPIRV_VAL)
    target_compile_definitions(ngfx PRIVATE NGFX_SPIRV_VAL_PATH="${NGFX_SPIRV_VAL}")
endif()
set_target_properties(ngfx PROPERTIES C_STANDARD 11 INTERPROCEDURAL_OPTIMIZATION OFF)
NoGraphicsAPI_disable_exceptions(ngfx)
if(MSVC)
    target_compile_options(ngfx PRIVATE /W4 /utf-8)
    target_compile_definitions(ngfx PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(ngfx PRIVATE -Wall -Wextra -Wno-missing-field-initializers)
endif()
if(APPLE)
    target_link_libraries(ngfx PUBLIC "-framework Metal" "-framework QuartzCore"
                          "-framework Foundation" c++ objc)
endif()

# --- Goose programs -------------------------------------------------------------
# ngfx_program(name source): `source` compiled to ${name}.c, with lib/ as a
# standard library directory ahead of Goose's own, then to an executable
# that links Goose's layers as well as ngfx: what a program does not call,
# the linker leaves out.
file(GLOB NGFX_GOOSE_LIBS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/lib/*.goose")
set(NGFX_GOOSE_OPT -O2 CACHE STRING "The Goose compiler's optimization level for programs")
function(ngfx_program name source)
    set(c "${CMAKE_BINARY_DIR}/programs/${name}.c")
    add_custom_command(
        OUTPUT "${c}"
        COMMAND "${CMAKE_COMMAND}" -E env "GOOSE_STDLIB=${GOOSE_DIR}/stdlib"
                "$<TARGET_FILE:goose>" ${NGFX_GOOSE_OPT} --standalone -o "${c}"
                --stdlib "${CMAKE_CURRENT_SOURCE_DIR}/lib" "${source}"
        DEPENDS "${source}" ${NGFX_GOOSE_LIBS} goose
        VERBATIM
        COMMENT "Compiling ${name} from Goose to C")
    add_executable(${name} "${c}")
    target_link_libraries(${name} PRIVATE ngfx goose_gfx goose_audio goose_ui)
    if(MSVC)
        # The generated C is the compiler's to vet, not ours.
        target_compile_options(${name} PRIVATE /W0)
    else()
        target_compile_options(${name} PRIVATE -w)
        target_link_libraries(${name} PRIVATE m Threads::Threads)
    endif()
    set_target_properties(${name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
endfunction()

if(NOT MSVC)
    find_package(Threads REQUIRED)
endif()

file(GLOB samples CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/samples/*.goose")
foreach(source IN LISTS samples)
    get_filename_component(name "${source}" NAME_WE)
    ngfx_program(${name} "${source}")
endforeach()

file(GLOB tests CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/test/*.goose")
foreach(source IN LISTS tests)
    get_filename_component(name "${source}" NAME_WE)
    ngfx_program(${name} "${source}")
endforeach()
