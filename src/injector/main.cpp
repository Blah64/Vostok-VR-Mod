#include "process_utils.h"

#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

void print_usage(const char* program_name) {
    std::cout
        << "RTV VR Mod - DLL Injector\n"
        << "\n"
        << "Usage: " << program_name << " [options]\n"
        << "\n"
        << "Options:\n"
        << "  --launch <exe>   Path to RTV.exe (launches the process suspended)\n"
        << "  --inject <dll>   Path to the bootstrap DLL to inject\n"
        << "  --attach <pid>   Attach to a running process instead of launching\n"
        << "  --help           Show this help message\n"
        << "\n"
        << "Examples:\n"
        << "  " << program_name << " --launch RTV.exe --inject rtv_vr_bootstrap.dll\n"
        << "  " << program_name << " --attach 12345 --inject rtv_vr_bootstrap.dll\n";
}

struct cli_args {
    std::filesystem::path launch_exe;
    std::filesystem::path inject_dll;
    DWORD attach_pid = 0;
    bool show_help = false;
};

bool parse_args(int argc, char* argv[], cli_args& out) {
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];

        if (arg == "--help" || arg == "-h") {
            out.show_help = true;
            return true;
        }

        if (arg == "--launch") {
            if (i + 1 >= argc) {
                spdlog::error("--launch requires an argument");
                return false;
            }
            out.launch_exe = argv[++i];
        } else if (arg == "--inject") {
            if (i + 1 >= argc) {
                spdlog::error("--inject requires an argument");
                return false;
            }
            out.inject_dll = argv[++i];
        } else if (arg == "--attach") {
            if (i + 1 >= argc) {
                spdlog::error("--attach requires an argument");
                return false;
            }
            char* end = nullptr;
            unsigned long pid = std::strtoul(argv[++i], &end, 10);
            if (end == argv[i] || *end != '\0' || pid == 0) {
                spdlog::error("--attach requires a valid numeric PID");
                return false;
            }
            out.attach_pid = static_cast<DWORD>(pid);
        } else {
            spdlog::error("Unknown argument: {}", arg);
            return false;
        }
    }

    return true;
}

void init_logging() {
    auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
    auto logger = std::make_shared<spdlog::logger>("injector", console_sink);
    logger->set_level(spdlog::level::debug);
    logger->set_pattern("[%H:%M:%S.%e] [%^%l%$] %v");
    spdlog::set_default_logger(logger);
}

} // anonymous namespace

int main(int argc, char* argv[]) {
    init_logging();

    cli_args args;
    if (!parse_args(argc, argv, args)) {
        print_usage(argv[0]);
        return 1;
    }

    if (args.show_help) {
        print_usage(argv[0]);
        return 0;
    }

    // Validate arguments.
    if (args.inject_dll.empty()) {
        spdlog::error("--inject <dll> is required");
        print_usage(argv[0]);
        return 1;
    }

    if (args.launch_exe.empty() && args.attach_pid == 0) {
        spdlog::error("Either --launch <exe> or --attach <pid> is required");
        print_usage(argv[0]);
        return 1;
    }

    if (!args.launch_exe.empty() && args.attach_pid != 0) {
        spdlog::error("--launch and --attach are mutually exclusive");
        return 1;
    }

    // Resolve the DLL path to an absolute path.
    fs::path dll_path = fs::absolute(args.inject_dll);
    if (!fs::exists(dll_path)) {
        spdlog::error("DLL not found: {}", dll_path.string());
        return 1;
    }
    spdlog::info("DLL path: {}", dll_path.string());

    HANDLE process = nullptr;
    bool launched = false;

    if (!args.launch_exe.empty()) {
        // Launch the target process in a suspended state.
        fs::path exe_path = fs::absolute(args.launch_exe);

        auto [proc_handle, pid] = rtv_vr::injector::launch_suspended(exe_path);
        if (!proc_handle) {
            spdlog::error("Failed to launch process");
            return 1;
        }

        process = proc_handle;
        launched = true;
        spdlog::info("Target process launched (PID {})", pid);
    } else {
        // Attach to an existing process.
        spdlog::info("Attaching to PID {}", args.attach_pid);

        process = OpenProcess(
            PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
            PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ,
            FALSE,
            args.attach_pid);

        if (!process) {
            spdlog::error("OpenProcess failed for PID {} (error {})",
                          args.attach_pid, GetLastError());
            return 1;
        }
    }

    // Inject the bootstrap DLL.
    bool injected = rtv_vr::injector::inject_dll(process, dll_path);
    if (!injected) {
        spdlog::error("DLL injection failed");
        if (launched) {
            spdlog::warn("Terminating suspended process due to injection failure");
            TerminateProcess(process, 1);
        }
        CloseHandle(process);
        return 1;
    }

    // Resume the process if we launched it.
    if (launched) {
        rtv_vr::injector::resume_process(process);
        spdlog::info("Process resumed");
    }

    CloseHandle(process);
    spdlog::info("Injection complete");
    return 0;
}
