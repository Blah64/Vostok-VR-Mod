#include "vk_dispatch_table.h"

#include <spdlog/spdlog.h>

namespace rtv_vr::vk {

DispatchTable& DispatchTable::get() {
    static DispatchTable instance;
    return instance;
}

bool DispatchTable::populate_instance(VkInstance instance,
                                      PFN_vkGetInstanceProcAddr gipa) {
    if (!gipa) {
        spdlog::error("DispatchTable: vkGetInstanceProcAddr is null");
        return false;
    }

    GetInstanceProcAddr = gipa;

    GetDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        gipa(instance, "vkGetDeviceProcAddr"));

    if (!GetDeviceProcAddr) {
        spdlog::error("DispatchTable: Failed to resolve vkGetDeviceProcAddr");
        return false;
    }

    spdlog::info("DispatchTable: Instance-level pointers populated");
    return true;
}

bool DispatchTable::populate_device(VkDevice device,
                                    PFN_vkGetDeviceProcAddr gdpa) {
    if (!gdpa) {
        spdlog::error("DispatchTable: vkGetDeviceProcAddr is null");
        return false;
    }

    GetDeviceProcAddr = gdpa;

    auto resolve = [&](const char* name) -> PFN_vkVoidFunction {
        PFN_vkVoidFunction fn = gdpa(device, name);
        if (!fn) {
            spdlog::warn("DispatchTable: Could not resolve {}", name);
        }
        return fn;
    };

    QueueSubmit =
        reinterpret_cast<PFN_vkQueueSubmit>(resolve("vkQueueSubmit"));
    CreateSwapchainKHR =
        reinterpret_cast<PFN_vkCreateSwapchainKHR>(resolve("vkCreateSwapchainKHR"));
    AcquireNextImageKHR =
        reinterpret_cast<PFN_vkAcquireNextImageKHR>(resolve("vkAcquireNextImageKHR"));
    CmdBeginRenderPass =
        reinterpret_cast<PFN_vkCmdBeginRenderPass>(resolve("vkCmdBeginRenderPass"));
    CmdEndRenderPass =
        reinterpret_cast<PFN_vkCmdEndRenderPass>(resolve("vkCmdEndRenderPass"));

    if (!QueueSubmit) {
        spdlog::error("DispatchTable: Critical function vkQueueSubmit missing");
        return false;
    }

    spdlog::info("DispatchTable: Device-level pointers populated");
    return true;
}

} // namespace rtv_vr::vk
