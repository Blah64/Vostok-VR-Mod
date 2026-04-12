#pragma once

#include <vulkan/vulkan.h>

namespace rtv_vr::vk {

/// Install MinHook-based hooks on vkGetInstanceProcAddr and
/// vkGetDeviceProcAddr exported by vulkan-1.dll.
bool install_hooks();

/// Remove all installed Vulkan hooks and uninitialize MinHook.
void remove_hooks();

// --- Hook trampolines exposed for dispatch interception ---

PFN_vkVoidFunction VKAPI_CALL hooked_vkGetInstanceProcAddr(VkInstance instance,
                                                            const char* pName);

PFN_vkVoidFunction VKAPI_CALL hooked_vkGetDeviceProcAddr(VkDevice device,
                                                          const char* pName);

VkResult VKAPI_CALL hooked_vkQueueSubmit(VkQueue queue,
                                         uint32_t submitCount,
                                         const VkSubmitInfo* pSubmits,
                                         VkFence fence);

VkResult VKAPI_CALL hooked_vkCreateSwapchainKHR(
    VkDevice device,
    const VkSwapchainCreateInfoKHR* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkSwapchainKHR* pSwapchain);

} // namespace rtv_vr::vk
