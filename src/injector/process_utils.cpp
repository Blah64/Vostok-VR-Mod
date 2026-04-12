#include "process_utils.h"

#include <TlHelp32.h>
#include <spdlog/spdlog.h>

namespace rtv_vr::injector {

DWORD find_process_by_name(const std::wstring& name) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        spdlog::error("CreateToolhelp32Snapshot failed (error {})", GetLastError());
        return 0;
    }

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);

    if (!Process32FirstW(snapshot, &entry)) {
        spdlog::error("Process32FirstW failed (error {})", GetLastError());
        CloseHandle(snapshot);
        return 0;
    }

    DWORD pid = 0;
    do {
        if (_wcsicmp(entry.szExeFile, name.c_str()) == 0) {
            pid = entry.th32ProcessID;
            break;
        }
    } while (Process32NextW(snapshot, &entry));

    CloseHandle(snapshot);

    if (pid == 0) {
        spdlog::warn("Process '{}' not found", std::string(name.begin(), name.end()));
    } else {
        spdlog::info("Found process '{}' with PID {}",
                      std::string(name.begin(), name.end()), pid);
    }

    return pid;
}

std::pair<HANDLE, DWORD> launch_suspended(const std::filesystem::path& exe_path,
                                          std::wstring extra_args) {
    if (!std::filesystem::exists(exe_path)) {
        spdlog::error("Executable not found: {}", exe_path.string());
        return {nullptr, 0};
    }

    // Build command line: quoted exe path followed by any extra arguments.
    std::wstring cmd_line = L"\"" + exe_path.wstring() + L"\"";
    if (!extra_args.empty()) {
        cmd_line += L" " + extra_args;
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};

    // CreateProcessW requires a mutable command-line buffer.
    std::vector<wchar_t> cmd_buf(cmd_line.begin(), cmd_line.end());
    cmd_buf.push_back(L'\0');

    BOOL ok = CreateProcessW(
        exe_path.c_str(),
        cmd_buf.data(),
        nullptr,        // process security attributes
        nullptr,        // thread security attributes
        FALSE,          // inherit handles
        CREATE_SUSPENDED,
        nullptr,        // environment
        exe_path.parent_path().c_str(),  // working directory
        &si,
        &pi);

    if (!ok) {
        spdlog::error("CreateProcessW failed for '{}' (error {})",
                      exe_path.string(), GetLastError());
        return {nullptr, 0};
    }

    spdlog::info("Launched '{}' suspended (PID {})", exe_path.string(), pi.dwProcessId);

    // We keep the process handle but close the thread handle — resume_process
    // will enumerate threads when needed.
    CloseHandle(pi.hThread);

    return {pi.hProcess, pi.dwProcessId};
}

bool inject_dll(HANDLE process, const std::filesystem::path& dll_path) {
    if (!process) {
        spdlog::error("inject_dll called with null process handle");
        return false;
    }

    std::filesystem::path abs_path = std::filesystem::absolute(dll_path);
    if (!std::filesystem::exists(abs_path)) {
        spdlog::error("DLL not found: {}", abs_path.string());
        return false;
    }

    std::wstring wide_path = abs_path.wstring();
    SIZE_T alloc_size = (wide_path.size() + 1) * sizeof(wchar_t);

    // Allocate memory in the target process for the DLL path string.
    void* remote_buf = VirtualAllocEx(process, nullptr, alloc_size,
                                      MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote_buf) {
        spdlog::error("VirtualAllocEx failed (error {})", GetLastError());
        return false;
    }

    spdlog::debug("Allocated {} bytes in target process at {:p}", alloc_size, remote_buf);

    // Write the DLL path into the allocated memory.
    if (!WriteProcessMemory(process, remote_buf, wide_path.c_str(), alloc_size, nullptr)) {
        spdlog::error("WriteProcessMemory failed (error {})", GetLastError());
        VirtualFreeEx(process, remote_buf, 0, MEM_RELEASE);
        return false;
    }

    // Resolve LoadLibraryW address. Because kernel32.dll is mapped at the same base
    // address in every process, we can use our own module's address.
    HMODULE kernel32 = GetModuleHandleW(L"kernel32.dll");
    if (!kernel32) {
        spdlog::error("GetModuleHandleW(kernel32.dll) failed (error {})", GetLastError());
        VirtualFreeEx(process, remote_buf, 0, MEM_RELEASE);
        return false;
    }

    auto load_library_addr = reinterpret_cast<LPTHREAD_START_ROUTINE>(
        GetProcAddress(kernel32, "LoadLibraryW"));
    if (!load_library_addr) {
        spdlog::error("GetProcAddress(LoadLibraryW) failed (error {})", GetLastError());
        VirtualFreeEx(process, remote_buf, 0, MEM_RELEASE);
        return false;
    }

    // Create a remote thread in the target process that calls LoadLibraryW with our path.
    HANDLE remote_thread = CreateRemoteThread(
        process,
        nullptr,            // security attributes
        0,                  // stack size (default)
        load_library_addr,
        remote_buf,         // argument to LoadLibraryW
        0,                  // creation flags
        nullptr);           // thread id

    if (!remote_thread) {
        spdlog::error("CreateRemoteThread failed (error {})", GetLastError());
        VirtualFreeEx(process, remote_buf, 0, MEM_RELEASE);
        return false;
    }

    spdlog::info("Remote thread created, waiting for DLL load...");

    // Wait for the remote thread to finish (LoadLibraryW returns).
    DWORD wait_result = WaitForSingleObject(remote_thread, 10000);
    if (wait_result != WAIT_OBJECT_0) {
        spdlog::error("WaitForSingleObject on remote thread returned {} (error {})",
                      wait_result, GetLastError());
        CloseHandle(remote_thread);
        VirtualFreeEx(process, remote_buf, 0, MEM_RELEASE);
        return false;
    }

    // Check the exit code of the remote thread (HMODULE returned by LoadLibraryW).
    DWORD exit_code = 0;
    GetExitCodeThread(remote_thread, &exit_code);
    CloseHandle(remote_thread);

    // Clean up the allocated memory in the target process.
    VirtualFreeEx(process, remote_buf, 0, MEM_RELEASE);

    if (exit_code == 0) {
        spdlog::error("LoadLibraryW returned NULL in target process — DLL load failed");
        return false;
    }

    spdlog::info("DLL injected successfully: {}", abs_path.string());
    return true;
}

void resume_process(HANDLE process) {
    if (!process) {
        spdlog::error("resume_process called with null process handle");
        return;
    }

    DWORD pid = GetProcessId(process);

    // Enumerate threads belonging to the target process and resume each one.
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        spdlog::error("CreateToolhelp32Snapshot (threads) failed (error {})", GetLastError());
        return;
    }

    THREADENTRY32 te{};
    te.dwSize = sizeof(te);

    int resumed_count = 0;
    if (Thread32First(snapshot, &te)) {
        do {
            if (te.th32OwnerProcessID == pid) {
                HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME, FALSE, te.th32ThreadID);
                if (thread) {
                    DWORD result = ResumeThread(thread);
                    if (result == static_cast<DWORD>(-1)) {
                        spdlog::warn("ResumeThread failed for thread {} (error {})",
                                     te.th32ThreadID, GetLastError());
                    } else {
                        ++resumed_count;
                    }
                    CloseHandle(thread);
                }
            }
        } while (Thread32Next(snapshot, &te));
    }

    CloseHandle(snapshot);
    spdlog::info("Resumed {} thread(s) for PID {}", resumed_count, pid);
}

} // namespace rtv_vr::injector
