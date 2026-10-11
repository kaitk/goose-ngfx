# The ngfx package's native part (ngfx.build): SDL3 from third_party/SDL,
# NoGraphicsAPI from third_party/NoGraphicsAPI, and the layer that
# ngfx.goose declares its extern fns against (native/), linked as the target
# ngfx. The Goose compiler builds it through a wrapper project of its own
# when a program imports ngfx (docs/development.md).

cmake_minimum_required(VERSION 3.25)
project(goose_ngfx C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# The C runtime of Goose's runtime object and packages.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

# --- SDL ----------------------------------------------------------------------
# Static, and configured as Goose's gfx package configures it
# (github.com/aardappel/goose_gfx, CMakeLists.txt) at the same commit: a
# program that imports ngfx and audio or ui links both packages' SDL, and the
# linker takes each object from whichever comes first, so the two must be
# the same build.
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/SDL/CMakeLists.txt")
    message(FATAL_ERROR "No third_party/SDL: git submodule update --init")
endif()
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
set(SDL_RENDER OFF CACHE BOOL "" FORCE)
set(SDL_OPENGL OFF CACHE BOOL "" FORCE)
set(SDL_OPENGLES OFF CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/third_party/SDL" "${CMAKE_CURRENT_BINARY_DIR}/SDL" EXCLUDE_FROM_ALL)

# --- the shader tools --------------------------------------------------------------
# For the layer's own shaders now, and as the defaults ngfx::slang runs
# later (native/ngfx_slang.cpp). The Goose compiler configures this project
# with no options of the user's, so the environment's NGFX_SLANGC, which
# ngfx::slang reads too, is the way to name another slangc. The Vulkan SDK
# puts an older slangc on PATH, which the search passes over.
set(NGFX_SLANGC_MIN 2026.18.2)
function(ngfx_slangc_ok result candidate)
    execute_process(COMMAND "${candidate}" -version OUTPUT_VARIABLE out ERROR_VARIABLE out
                    RESULT_VARIABLE code)
    string(REGEX MATCH "[0-9]+[.][0-9]+([.][0-9]+)?" version "${out}")
    if(NOT code EQUAL 0 OR NOT version OR version VERSION_LESS NGFX_SLANGC_MIN)
        set(${result} FALSE PARENT_SCOPE)
    endif()
endfunction()
if(DEFINED ENV{NGFX_SLANGC} AND NOT NGFX_SLANGC)
    set(NGFX_SLANGC "$ENV{NGFX_SLANGC}" CACHE FILEPATH "slangc ${NGFX_SLANGC_MIN} or later")
endif()
find_program(NGFX_SLANGC NAMES slangc HINTS "${CMAKE_CURRENT_SOURCE_DIR}/../slang/bin"
             VALIDATOR ngfx_slangc_ok DOC "slangc ${NGFX_SLANGC_MIN} or later")
find_program(NGFX_SPIRV_VAL NAMES spirv-val HINTS "$ENV{VULKAN_SDK}/Bin" "$ENV{VULKAN_SDK}/bin"
             DOC "spirv-val, to validate the SPIR-V ngfx::slang makes")
set(slangc_ok TRUE)
if(NGFX_SLANGC)
    ngfx_slangc_ok(slangc_ok "${NGFX_SLANGC}")
endif()
if(NOT NGFX_SLANGC OR NOT slangc_ok)
    message(FATAL_ERROR "No slangc ${NGFX_SLANGC_MIN} or later (${NGFX_SLANGC}): set NGFX_SLANGC "
                        "to one, or put it on PATH ahead of the Vulkan SDK's (docs/development.md)")
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
add_subdirectory("${NGFX_NG}" "${CMAKE_CURRENT_BINARY_DIR}/NoGraphicsAPI" EXCLUDE_FROM_ALL)

set(NGFX_OUT "${CMAKE_CURRENT_BINARY_DIR}/shaders")

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
# PRIVATE, so only the link closure reaches the targets of Goose's wrapper
# project, whose top level enables C alone and can't meet NoGraphicsAPI's
# cxx_std_20 (docs/goose-findings.md).
target_link_libraries(ngfx PRIVATE SDL3::SDL3-static NoGraphicsAPI::NoGraphicsAPI NoGraphicsAPIUtility::uploads
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
    target_link_libraries(ngfx PRIVATE "-framework Metal" "-framework QuartzCore"
                          "-framework Foundation" c++ objc)
endif()
