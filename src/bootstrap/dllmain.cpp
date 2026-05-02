#include "command_line_patch.h"
#include "extension_deployer.h"

#include <filesystem>
#include <string>

#include <Windows.h>
#include <MinHook.h>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>

#define RTV_VR_VERSION "0.1.0"

namespace fs = std::filesystem;

namespace {

bool init_logging() {
    try {
        // Determine log file path: <exe_dir>/VR Mod/logs/rtv_vr.log
        wchar_t exe_path[MAX_PATH];
        DWORD len = GetModuleFileNameW(NULL, exe_path, MAX_PATH);
        if (len == 0 || len >= MAX_PATH) {
            return false;
        }

        fs::path log_dir = fs::path(exe_path).parent_path() / "VR Mod" / "logs";
        std::error_code ec;
        fs::create_directories(log_dir, ec);
        if (ec) {
            return false;
        }

        fs::path log_file = log_dir / "rtv_vr.log";

        auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        auto file_sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(
            log_file.string(), /*truncate=*/true);

        auto logger = std::make_shared<spdlog::logger>(
            "rtv_vr", spdlog::sinks_init_list{ console_sink, file_sink });

        logger->set_level(spdlog::level::debug);
        logger->flush_on(spdlog::level::debug);
        spdlog::set_default_logger(logger);

        return true;
    } catch (const spdlog::spdlog_ex &ex) {
        OutputDebugStringA("spdlog init failed: ");
        OutputDebugStringA(ex.what());
        OutputDebugStringA("\n");
        return false;
    }
}

bool init_minhook() {
    MH_STATUS status = MH_Initialize();
    if (status != MH_OK && status != MH_ERROR_ALREADY_INITIALIZED) {
        spdlog::error("MH_Initialize failed: {}", MH_StatusToString(status));
        return false;
    }
    return true;
}

void shutdown_minhook() {
    MH_Uninitialize();
}

} // anonymous namespace

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH: {
        DisableThreadLibraryCalls(hModule);

        if (!init_logging()) {
            OutputDebugStringA("[rtv_vr] Failed to initialize logging\n");
            return FALSE;
        }

        spdlog::info("=== Road to Vostok VR Mod v{} ===", RTV_VR_VERSION);
        spdlog::info("Bootstrap DLL loaded");

        if (!init_minhook()) {
            spdlog::error("Failed to initialize MinHook, aborting");
            spdlog::shutdown();
            return FALSE;
        }

        if (!rtv_vr::bootstrap::install_command_line_patch()) {
            spdlog::error("Failed to install command line patch, aborting");
            shutdown_minhook();
            spdlog::shutdown();
            return FALSE;
        }

        if (!rtv_vr::bootstrap::deploy_extension_files()) {
            spdlog::error("Failed to deploy extension files, aborting");
            rtv_vr::bootstrap::remove_command_line_patch();
            shutdown_minhook();
            spdlog::shutdown();
            return FALSE;
        }

        spdlog::info("Bootstrap initialization complete");
        break;
    }

    case DLL_PROCESS_DETACH: {
        spdlog::info("Bootstrap DLL unloading...");
        rtv_vr::bootstrap::remove_command_line_patch();
        shutdown_minhook();
        spdlog::info("Shutdown complete");
        spdlog::shutdown();
        break;
    }

    default:
        break;
    }

    return TRUE;
}
