cmake_minimum_required(VERSION 3.24)
project(rtv_vr_mod VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Use dynamic CRT consistently across all targets
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

# Options
option(RTV_VR_BUILD_INJECTOR "Build the injector utility" ON)
option(RTV_VR_BUILD_TESTS "Build unit tests" OFF)

# CMake modules
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CompilerWarnings)

# --- External Dependencies ---

# spdlog
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/spdlog/CMakeLists.txt")
    message(STATUS "Fetching spdlog...")
    include(FetchContent)
    FetchContent_Declare(spdlog
        GIT_REPOSITORY https://github.com/gabime/spdlog.git
        GIT_TAG        v1.14.1
        SOURCE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/spdlog"
    )
    FetchContent_MakeAvailable(spdlog)
else()
    add_subdirectory(external/spdlog EXCLUDE_FROM_ALL)
endif()

# MinHook
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/minhook/CMakeLists.txt")
    message(STATUS "Fetching MinHook...")
    include(FetchContent)
    FetchContent_Declare(minhook
        GIT_REPOSITORY https://github.com/TsudaKageyu/minhook.git
        GIT_TAG        v1.3.4
        SOURCE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/minhook"
    )
    FetchContent_MakeAvailable(minhook)
else()
    add_subdirectory(external/minhook EXCLUDE_FROM_ALL)
endif()

# nlohmann_json
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/nlohmann_json/CMakeLists.txt")
    message(STATUS "Fetching nlohmann_json...")
    include(FetchContent)
    set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(nlohmann_json
        GIT_REPOSITORY https://github.com/nlohmann/json.git
        GIT_TAG        v3.11.3
        SOURCE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/nlohmann_json"
    )
    FetchContent_MakeAvailable(nlohmann_json)
else()
    set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
    add_subdirectory(external/nlohmann_json EXCLUDE_FROM_ALL)
endif()

# godot-cpp
include(GodotCPP)

# --- Sub-projects ---
add_subdirectory(src/bootstrap)
add_subdirectory(src/gdextension)

if(RTV_VR_BUILD_INJECTOR)
    add_subdirectory(src/injector)
endif()

if(RTV_VR_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# --- Install rules ---
set(GAME_DIR "${CMAKE_SOURCE_DIR}/..")

install(TARGETS rtv_vr_bootstrap
    RUNTIME DESTINATION "${GAME_DIR}"
    LIBRARY DESTINATION "${GAME_DIR}"
)

install(TARGETS rtv_vr_mod
    RUNTIME DESTINATION "${GAME_DIR}"
    LIBRARY DESTINATION "${GAME_DIR}"
)

if(RTV_VR_BUILD_INJECTOR)
    install(TARGETS rtv_vr_injector
        RUNTIME DESTINATION "${GAME_DIR}/VR Mod/bin"
    )
endif()

install(FILES resources/override.cfg DESTINATION "${GAME_DIR}")
install(FILES resources/rtv_vr_mod.gdextension DESTINATION "${GAME_DIR}")
install(DIRECTORY config/ DESTINATION "${GAME_DIR}/VR Mod/config")
install(FILES scripts/launch_vr.bat DESTINATION "${GAME_DIR}")
