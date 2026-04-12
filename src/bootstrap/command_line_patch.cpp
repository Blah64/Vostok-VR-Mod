#include "command_line_patch.h"

#include <string>

#include <Windows.h>
#include <MinHook.h>
#include <spdlog/spdlog.h>

namespace rtv_vr::bootstrap {

namespace {

using GetCommandLineW_t = LPWSTR(WINAPI *)();
GetCommandLineW_t g_original_GetCommandLineW = nullptr;
std::wstring g_modified_command_line;
bool g_hook_installed = false;

LPWSTR WINAPI hooked_GetCommandLineW() {
    if (!g_modified_command_line.empty()) {
        return g_modified_command_line.data();
    }

    LPWSTR original = g_original_GetCommandLineW();
    if (!original) {
        return original;
    }

    std::wstring cmd_line(original);

    if (cmd_line.find(L"--rendering-method") != std::wstring::npos) {
        spdlog::info("Command line already contains --rendering-method, no patch needed");
        g_modified_command_line = std::move(cmd_line);
    } else {
        g_modified_command_line = cmd_line + L" --rendering-method mobile --rendering-driver vulkan";
        spdlog::info("Appended '--rendering-method mobile --rendering-driver vulkan' to command line");
    }

    return g_modified_command_line.data();
}

} // anonymous namespace

bool install_command_line_patch() {
    spdlog::info("Installing command line patch...");

    HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    if (!kernel32) {
        spdlog::error("Failed to get handle to kernel32.dll");
        return false;
    }

    auto target = reinterpret_cast<GetCommandLineW_t>(
        GetProcAddress(kernel32, "GetCommandLineW"));
    if (!target) {
        spdlog::error("Failed to find GetCommandLineW in kernel32.dll");
        return false;
    }

    MH_STATUS status = MH_CreateHook(
        reinterpret_cast<LPVOID>(target),
        reinterpret_cast<LPVOID>(&hooked_GetCommandLineW),
        reinterpret_cast<LPVOID *>(&g_original_GetCommandLineW));

    if (status != MH_OK) {
        spdlog::error("MH_CreateHook failed for GetCommandLineW: {}", MH_StatusToString(status));
        return false;
    }

    status = MH_EnableHook(reinterpret_cast<LPVOID>(target));
    if (status != MH_OK) {
        spdlog::error("MH_EnableHook failed for GetCommandLineW: {}", MH_StatusToString(status));
        MH_RemoveHook(reinterpret_cast<LPVOID>(target));
        return false;
    }

    g_hook_installed = true;
    spdlog::info("Command line patch installed successfully");
    return true;
}

void remove_command_line_patch() {
    if (!g_hook_installed) {
        return;
    }

    spdlog::info("Removing command line patch...");

    HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    if (kernel32) {
        auto target = reinterpret_cast<LPVOID>(
            GetProcAddress(kernel32, "GetCommandLineW"));
        if (target) {
            MH_DisableHook(target);
            MH_RemoveHook(target);
        }
    }

    g_hook_installed = false;
    g_modified_command_line.clear();
    spdlog::info("Command line patch removed");
}

} // namespace rtv_vr::bootstrap
