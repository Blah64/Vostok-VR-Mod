#pragma once

#include <vulkan/vulkan.h>

namespace rtv_vr::vk {

/// Caches Vulkan function pointers for instance-level and device-level
/// dispatch. A process-wide singleton is exposed via get().
struct DispatchTable {
    // --- Instance-level ---
    PFN_vkGetInstanceProcAddr GetInstanceProcAddr = nullptr;
    PFN_vkGetDeviceProcAddr   GetDeviceProcAddr   = nullptr;

    // --- Device-level ---
    PFN_vkQueueSubmit          QueueSubmit          = nullptr;
    PFN_vkCreateSwapchainKHR   CreateSwapchainKHR   = nullptr;
    PFN_vkAcquireNextImageKHR  AcquireNextImageKHR  = nullptr;
    PFN_vkCmdBeginRenderPass   CmdBeginRenderPass   = nullptr;
    PFN_vkCmdEndRenderPass     CmdEndRenderPass     = nullptr;

    /// Fill instance-level pointers from the given VkInstance.
    /// Returns false if any critical pointer could not be resolved.
    bool populate_instance(VkInstance instance, PFN_vkGetInstanceProcAddr gipa);

    /// Fill device-level pointers from the given VkDevice.
    /// Returns false if any critical pointer could not be resolved.
    bool populate_device(VkDevice device, PFN_vkGetDeviceProcAddr gdpa);

    /// Process-wide singleton.
    static DispatchTable& get();
};

} // namespace rtv_vr::vk
