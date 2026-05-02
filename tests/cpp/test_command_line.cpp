// tests/cpp/test_command_line.cpp
//
// Unit tests for command_line_logic.h. Uses a tiny in-file assertion harness
// so the test target has no external test-framework dependency. Each test is
// a void function returning the assertion-failed count via a shared counter.
//
// CMake registers the binary with CTest; nonzero exit code = failure.

#include "command_line_logic.h"

#include <cwchar>
#include <iostream>
#include <string>

namespace {

int g_failures = 0;
int g_passes = 0;
std::string g_current;

void check(bool cond, const char* msg) {
    if (cond) {
        ++g_passes;
        std::cout << "  PASS: " << msg << "\n";
    } else {
        ++g_failures;
        std::cout << "  FAIL: " << g_current << ": " << msg << "\n";
    }
}

void section(const char* name) {
    g_current = name;
    std::cout << "\n== " << name << " ==\n";
}

// --- tests --------------------------------------------------------------

void test_appends_when_missing() {
    section("test_appends_when_missing");
    auto out = rtv_vr::bootstrap::compute_patched_command_line(L"RTV.exe --foo bar");
    check(out == L"RTV.exe --foo bar --rendering-method mobile --rendering-driver vulkan",
          "appends rendering-method args when absent");
}

void test_idempotent_when_already_patched() {
    section("test_idempotent_when_already_patched");
    std::wstring already = L"RTV.exe --rendering-method mobile --rendering-driver vulkan";
    auto out = rtv_vr::bootstrap::compute_patched_command_line(already);
    check(out == already, "no double-append when --rendering-method already present");
}

void test_empty_input_gets_patched() {
    section("test_empty_input_gets_patched");
    auto out = rtv_vr::bootstrap::compute_patched_command_line(L"");
    check(out == L" --rendering-method mobile --rendering-driver vulkan",
          "empty input still receives the patch (with leading space)");
}

void test_partial_match_does_not_skip() {
    section("test_partial_match_does_not_skip");
    // "--rendering-driver vulkan" alone does NOT contain "--rendering-method"
    // so the patcher should still append.
    auto out = rtv_vr::bootstrap::compute_patched_command_line(L"RTV.exe --rendering-driver vulkan");
    check(out.find(L"--rendering-method") != std::wstring::npos,
          "partial match (driver only) still triggers append");
    // But the result should now contain rendering-method exactly once.
    size_t first = out.find(L"--rendering-method");
    size_t last = out.rfind(L"--rendering-method");
    check(first == last, "only one --rendering-method after patch");
}

void test_double_invocation_idempotent() {
    section("test_double_invocation_idempotent");
    auto once = rtv_vr::bootstrap::compute_patched_command_line(L"RTV.exe");
    auto twice = rtv_vr::bootstrap::compute_patched_command_line(once);
    check(once == twice, "patching twice yields the same output");
}

void test_is_patched_predicate() {
    section("test_is_patched_predicate");
    check(!rtv_vr::bootstrap::is_patched_command_line(L"RTV.exe"),
          "raw command line is not patched");
    check(rtv_vr::bootstrap::is_patched_command_line(
              L"RTV.exe --rendering-method mobile --rendering-driver vulkan"),
          "patched command line reads as patched");
}

} // namespace

int main() {
    std::cout << "================================================\n";
    std::cout << "Road to Vostok VR Mod - C++ test suite\n";
    std::cout << "================================================\n";

    test_appends_when_missing();
    test_idempotent_when_already_patched();
    test_empty_input_gets_patched();
    test_partial_match_does_not_skip();
    test_double_invocation_idempotent();
    test_is_patched_predicate();

    std::cout << "\n================================================\n";
    std::cout << "C++ tests: " << g_passes << " passed, " << g_failures << " failed\n";
    return g_failures == 0 ? 0 : 1;
}
