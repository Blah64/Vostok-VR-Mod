# tests/CMakeLists.txt
#
# Native C++ unit tests for the bootstrap and gdextension modules.
# Activated via -DRTV_VR_BUILD_TESTS=ON. Uses CTest for registration; no
# external test framework dependency — each test_*.cpp ships its own
# in-file assertion harness and reports nonzero exit on failure.

# command-line patcher logic — pure header, no MinHook dependency.
add_executable(test_command_line cpp/test_command_line.cpp)
target_include_directories(test_command_line PRIVATE
    "${CMAKE_SOURCE_DIR}/src/bootstrap"
)
add_test(NAME command_line_patcher COMMAND test_command_line)
