#include "vulkan_hook_installer.h"

#include <spdlog/spdlog.h>

namespace rtv_vr::bootstrap {

bool install_vulkan_hooks() {
    spdlog::info("Vulkan hooks not yet implemented (stub)");
    return true;
}

void remove_vulkan_hooks() {
    spdlog::debug("Vulkan hook removal not yet implemented (stub)");
}

} // namespace rtv_vr::bootstrap
