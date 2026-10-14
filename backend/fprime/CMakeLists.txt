# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

cmake_minimum_required(VERSION 3.26)
project(OrbitLab LANGUAGES C CXX)
set(FPRIME_INCLUDE_FRAMEWORK_CODE OFF)
find_package(FPrime REQUIRED PATHS "$ENV{SLX_BACKEND_HOME}/fprime")
register_fprime_project()
add_subdirectory("$ENV{SLX_BACKEND_HOME}/fprime" F-Prime)
# GCC 11 reports a guarded tracker copy as maybe-uninitialized under -O3.
# Keep the warning visible without changing or weakening other upstream checks.
if(TARGET Svc_CmdDispatcher AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 12)
    target_compile_options(Svc_CmdDispatcher PRIVATE -Wno-error=maybe-uninitialized)
endif()
set(CMAKE_CXX_STANDARD 17)
include_directories("${CMAKE_CURRENT_LIST_DIR}/../../core/include")
# F Prime 4.3's wrapper passes a boolean to subprocess when imports are absent.
# Keep the upstream generator and supply an adapter with an optional imports argument.
set(FPRIME_FPP_TO_DICT_WRAPPER "${CMAKE_CURRENT_LIST_DIR}/tools/fpp_to_dict.py")
if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/../../private/core/mission.cpp")
    add_library(slx-mission-core SHARED ../../private/core/mission.cpp)
    target_include_directories(slx-mission-core PUBLIC ../../core/include)
    target_compile_definitions(slx-mission-core PRIVATE SLX_CORE_BUILD)
    set_target_properties(slx-mission-core PROPERTIES OUTPUT_NAME "SiliconLogiX.OrbitLab.Core" PREFIX "" CXX_VISIBILITY_PRESET hidden)
else()
    set(SLX_ORBIT_CORE_LIBRARY "${CMAKE_CURRENT_LIST_DIR}/../../sdk/linux-x86_64/SiliconLogiX.OrbitLab.Core.so" CACHE FILEPATH "Approved Linux numerical core")
    if(NOT EXISTS "${SLX_ORBIT_CORE_LIBRARY}")
        message(FATAL_ERROR "Provide the ABI-compatible Linux numerical core SDK")
    endif()
    add_library(slx-mission-core SHARED IMPORTED)
    set_target_properties(slx-mission-core PROPERTIES IMPORTED_LOCATION "${SLX_ORBIT_CORE_LIBRARY}")
endif()
add_fprime_subdirectory("${CMAKE_CURRENT_LIST_DIR}/Mission")
add_fprime_subdirectory("${CMAKE_CURRENT_LIST_DIR}/Transport")
add_fprime_subdirectory("${CMAKE_CURRENT_LIST_DIR}/Top")
register_fprime_deployment(OrbitLab SOURCES "${CMAKE_CURRENT_LIST_DIR}/Main.cpp" DEPENDS OrbitLab_Top)
target_link_libraries(OrbitLab PRIVATE slx-mission-core)
