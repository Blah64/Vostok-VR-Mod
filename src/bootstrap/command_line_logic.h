#pragma once

// command_line_logic.h
//
// Pure, header-only helpers for the command-line patcher. Split out from
// command_line_patch.cpp so the logic can be unit-tested without invoking
// MinHook / GetCommandLineW. The actual hook in command_line_patch.cpp
// calls into compute_patched_command_line().
//
// Idempotency contract: if the input already contains "--rendering-method"
// anywhere, the function returns it unchanged. Otherwise it appends
// " --rendering-method mobile --rendering-driver vulkan".

#include <string>

namespace rtv_vr::bootstrap {

inline constexpr const wchar_t kRenderingMethodFlag[] = L"--rendering-method";
inline constexpr const wchar_t kAppendedArgs[] = L" --rendering-method mobile --rendering-driver vulkan";

inline std::wstring compute_patched_command_line(const std::wstring& original) {
    if (original.find(kRenderingMethodFlag) != std::wstring::npos) {
        return original;
    }
    return original + kAppendedArgs;
}

// True iff the input string is in the post-patch form (already contains the flag).
inline bool is_patched_command_line(const std::wstring& cmd) {
    return cmd.find(kRenderingMethodFlag) != std::wstring::npos;
}

} // namespace rtv_vr::bootstrap
