#include "extension_deployer.h"

#include <filesystem>
#include <string>
#include <vector>

#include <Windows.h>
#include <spdlog/spdlog.h>

namespace fs = std::filesystem;

namespace rtv_vr::bootstrap {

namespace {

/// Files that we deploy into the exe directory.
const std::vector<std::pair<fs::path, fs::path>> k_deploy_manifest = {
    { "resources/override.cfg",              "override.cfg" },
    { "resources/vr_mod_init.gd",            "vr_mod_init.gd" },
    { "resources/rtv_vr_mod.gdextension",    "rtv_vr_mod.gdextension" },
};

/// Optional files that are copied if present but whose absence is not fatal.
const std::vector<std::pair<fs::path, fs::path>> k_optional_manifest = {
    { "rtv_vr_mod.dll", "rtv_vr_mod.dll" },
};

fs::path get_exe_directory() {
    wchar_t buf[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, buf, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) {
        spdlog::error("GetModuleFileNameW failed (error {})", GetLastError());
        return {};
    }
    return fs::path(buf).parent_path();
}

fs::path find_vr_mod_directory(const fs::path &exe_dir) {
    fs::path vr_mod_dir = exe_dir / "VR Mod";
    if (fs::is_directory(vr_mod_dir)) {
        return vr_mod_dir;
    }
    spdlog::error("VR Mod directory not found at: {}", vr_mod_dir.string());
    return {};
}

} // anonymous namespace

bool deploy_extension_files() {
    spdlog::info("Deploying extension files...");

    fs::path exe_dir = get_exe_directory();
    if (exe_dir.empty()) {
        return false;
    }
    spdlog::info("Exe directory: {}", exe_dir.string());

    fs::path vr_mod_dir = find_vr_mod_directory(exe_dir);
    if (vr_mod_dir.empty()) {
        return false;
    }
    spdlog::info("VR Mod directory: {}", vr_mod_dir.string());

    std::error_code ec;

    // Deploy required files.
    for (const auto &[src_rel, dst_name] : k_deploy_manifest) {
        fs::path src = vr_mod_dir / src_rel;
        fs::path dst = exe_dir / dst_name;

        if (!fs::exists(src)) {
            spdlog::error("Required file not found: {}", src.string());
            return false;
        }

        fs::copy_file(src, dst, fs::copy_options::overwrite_existing, ec);
        if (ec) {
            spdlog::error("Failed to copy {} -> {}: {}", src.string(), dst.string(), ec.message());
            return false;
        }
        spdlog::info("Deployed: {} -> {}", src_rel.string(), dst.string());
    }

    // Deploy optional files.
    for (const auto &[src_rel, dst_name] : k_optional_manifest) {
        fs::path src = vr_mod_dir / src_rel;
        fs::path dst = exe_dir / dst_name;

        if (!fs::exists(src)) {
            spdlog::debug("Optional file not present, skipping: {}", src.string());
            continue;
        }

        fs::copy_file(src, dst, fs::copy_options::overwrite_existing, ec);
        if (ec) {
            spdlog::warn("Failed to copy optional file {} -> {}: {}", src.string(), dst.string(), ec.message());
        } else {
            spdlog::info("Deployed optional: {} -> {}", src_rel.string(), dst.string());
        }
    }

    spdlog::info("Extension files deployed successfully");
    return true;
}

void cleanup_extension_files() {
    spdlog::info("Cleaning up deployed extension files...");

    fs::path exe_dir = get_exe_directory();
    if (exe_dir.empty()) {
        return;
    }

    std::error_code ec;

    auto remove_file = [&](const char *name) {
        fs::path p = exe_dir / name;
        if (fs::exists(p)) {
            fs::remove(p, ec);
            if (ec) {
                spdlog::warn("Failed to remove {}: {}", p.string(), ec.message());
            } else {
                spdlog::info("Removed: {}", p.string());
            }
        }
    };

    for (const auto &[_, dst_name] : k_deploy_manifest) {
        remove_file(dst_name.string().c_str());
    }
    for (const auto &[_, dst_name] : k_optional_manifest) {
        remove_file(dst_name.string().c_str());
    }

    spdlog::info("Cleanup complete");
}

} // namespace rtv_vr::bootstrap
