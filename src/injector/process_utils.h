#pragma once

#include <Windows.h>
#include <cstdint>
#include <filesystem>
#include <string>
#include <utility>

namespace rtv_vr::injector {

/// Finds a running process by executable name and returns its PID.
/// Returns 0 if the process is not found.
DWORD find_process_by_name(const std::wstring& name);

/// Launches an executable in a suspended state.
/// Returns (process handle, PID) on success, or (nullptr, 0) on failure.
std::pair<HANDLE, DWORD> launch_suspended(const std::filesystem::path& exe_path,
                                          std::wstring extra_args = L"");

/// Injects a DLL into the target process using VirtualAllocEx + CreateRemoteThread + LoadLibraryW.
/// Returns true on success.
bool inject_dll(HANDLE process, const std::filesystem::path& dll_path);

/// Resumes the main thread of a suspended process.
void resume_process(HANDLE process);

} // namespace rtv_vr::injector
