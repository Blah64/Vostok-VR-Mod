# Fetch and configure godot-cpp bindings for Godot 4.6
include(FetchContent)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/godot-cpp/CMakeLists.txt")
    message(STATUS "Fetching godot-cpp...")
    FetchContent_Declare(godot-cpp
        GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
        GIT_TAG        godot-4.4-stable
        SOURCE_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/external/godot-cpp"
    )
    FetchContent_MakeAvailable(godot-cpp)
else()
    add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/external/godot-cpp" godot-cpp EXCLUDE_FROM_ALL)
endif()
