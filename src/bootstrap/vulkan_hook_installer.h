#pragma once

namespace rtv_vr::bootstrap {

/// Installs hooks for Vulkan API interception (e.g. vkCreateInstance).
bool install_vulkan_hooks();

/// Removes Vulkan hooks.
void remove_vulkan_hooks();

} // namespace rtv_vr::bootstrap
