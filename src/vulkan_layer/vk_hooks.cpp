#include "vk_hooks.h"
#include "vk_dispatch_table.h"
#include "perf_overlay.h"

#include <MinHook.h>
#include <spdlog/spdlog.h>

#include <cstring>

namespace rtv_vr::vk {

// Original function pointers saved by MinHook.
static PFN_vkGetInstanceProcAddr g_real_vkGetInstanceProcAddr = nullptr;
static PFN_vkGetDeviceProcAddr   g_real_vkGetDeviceProcAddr   = nullptr;

// ---------------------------------------------------------------------------
// Hook installation / removal
// ---------------------------------------------------------------------------

bool install_hooks() {
    if (MH_Initialize() != MH_OK) {
        spdlog::error("vk_hooks: MH_Initialize failed");
        return false;
    }

    HMODULE vulkan_module = GetModuleHandleA("vulkan-1.dll");
    if (!vulkan_module) {
        spdlog::error("vk_hooks: Could not find vulkan-1.dll module");
        MH_Uninitialize();
        return false;
    }

    auto real_gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
        GetProcAddress(vulkan_module, "vkGetInstanceProcAddr"));
    auto real_gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        GetProcAddress(vulkan_module, "vkGetDeviceProcAddr"));

    if (!real_gipa || !real_gdpa) {
        spdlog::error("vk_hooks: Failed to locate Vulkan entry points in vulkan-1.dll");
        MH_Uninitialize();
        return false;
    }

    // Hook vkGetInstanceProcAddr
    MH_STATUS status = MH_CreateHook(
        reinterpret_cast<LPVOID>(real_gipa),
        reinterpret_cast<LPVOID>(&hooked_vkGetInstanceProcAddr),
        reinterpret_cast<LPVOID*>(&g_real_vkGetInstanceProcAddr));
    if (status != MH_OK) {
        spdlog::error("vk_hooks: MH_CreateHook(vkGetInstanceProcAddr) failed: {}",
                       MH_StatusToString(status));
        MH_Uninitialize();
        return false;
    }

    // Hook vkGetDeviceProcAddr
    status = MH_CreateHook(
        reinterpret_cast<LPVOID>(real_gdpa),
        reinterpret_cast<LPVOID>(&hooked_vkGetDeviceProcAddr),
        reinterpret_cast<LPVOID*>(&g_real_vkGetDeviceProcAddr));
    if (status != MH_OK) {
        spdlog::error("vk_hooks: MH_CreateHook(vkGetDeviceProcAddr) failed: {}",
                       MH_StatusToString(status));
        MH_Uninitialize();
        return false;
    }

    // Enable both hooks
    if (MH_EnableHook(MH_ALL_HOOKS) != MH_OK) {
        spdlog::error("vk_hooks: MH_EnableHook(MH_ALL_HOOKS) failed");
        MH_Uninitialize();
        return false;
    }

    spdlog::info("vk_hooks: Vulkan hooks installed successfully");
    return true;
}

void remove_hooks() {
    MH_DisableHook(MH_ALL_HOOKS);
    MH_Uninitialize();
    g_real_vkGetInstanceProcAddr = nullptr;
    g_real_vkGetDeviceProcAddr   = nullptr;
    spdlog::info("vk_hooks: All Vulkan hooks removed");
}

// ---------------------------------------------------------------------------
// Hooked vkGetInstanceProcAddr
// ---------------------------------------------------------------------------

PFN_vkVoidFunction VKAPI_CALL hooked_vkGetInstanceProcAddr(VkInstance instance,
                                                            const char* pName) {
    if (!pName) {
        return g_real_vkGetInstanceProcAddr
                   ? g_real_vkGetInstanceProcAddr(instance, pName)
                   : nullptr;
    }

    // Intercept known function names and return our hooks.
    if (std::strcmp(pName, "vkGetInstanceProcAddr") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&hooked_vkGetInstanceProcAddr);
    }
    if (std::strcmp(pName, "vkGetDeviceProcAddr") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&hooked_vkGetDeviceProcAddr);
    }
    if (std::strcmp(pName, "vkQueueSubmit") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&hooked_vkQueueSubmit);
    }
    if (std::strcmp(pName, "vkCreateSwapchainKHR") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&hooked_vkCreateSwapchainKHR);
    }

    // Delegate everything else to the real implementation.
    return g_real_vkGetInstanceProcAddr
               ? g_real_vkGetInstanceProcAddr(instance, pName)
               : nullptr;
}

// ---------------------------------------------------------------------------
// Hooked vkGetDeviceProcAddr
// ---------------------------------------------------------------------------

PFN_vkVoidFunction VKAPI_CALL hooked_vkGetDeviceProcAddr(VkDevice device,
                                                          const char* pName) {
    if (!pName) {
        return g_real_vkGetDeviceProcAddr
                   ? g_real_vkGetDeviceProcAddr(device, pName)
                   : nullptr;
    }

    if (std::strcmp(pName, "vkQueueSubmit") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&hooked_vkQueueSubmit);
    }
    if (std::strcmp(pName, "vkCreateSwapchainKHR") == 0) {
        return reinterpret_cast<PFN_vkVoidFunction>(&hooked_vkCreateSwapchainKHR);
    }

    return g_real_vkGetDeviceProcAddr
               ? g_real_vkGetDeviceProcAddr(device, pName)
               : nullptr;
}

// ---------------------------------------------------------------------------
// Hooked vkQueueSubmit
// ---------------------------------------------------------------------------

VkResult VKAPI_CALL hooked_vkQueueSubmit(VkQueue queue,
                                         uint32_t submitCount,
                                         const VkSubmitInfo* pSubmits,
                                         VkFence fence) {
    spdlog::trace("vk_hooks: vkQueueSubmit called (submitCount={})", submitCount);

    // Notify the performance overlay about the frame submission.
    perf_overlay::on_frame_submitted();

    auto& dt = DispatchTable::get();
    if (dt.QueueSubmit) {
        return dt.QueueSubmit(queue, submitCount, pSubmits, fence);
    }

    spdlog::error("vk_hooks: Real vkQueueSubmit is null, cannot forward call");
    return VK_ERROR_INITIALIZATION_FAILED;
}

// ---------------------------------------------------------------------------
// Hooked vkCreateSwapchainKHR
// ---------------------------------------------------------------------------

VkResult VKAPI_CALL hooked_vkCreateSwapchainKHR(
    VkDevice device,
    const VkSwapchainCreateInfoKHR* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkSwapchainKHR* pSwapchain) {

    if (pCreateInfo) {
        spdlog::info("vk_hooks: vkCreateSwapchainKHR - "
                      "imageExtent={}x{}, imageFormat={}, presentMode={}, "
                      "minImageCount={}",
                      pCreateInfo->imageExtent.width,
                      pCreateInfo->imageExtent.height,
                      static_cast<int>(pCreateInfo->imageFormat),
                      static_cast<int>(pCreateInfo->presentMode),
                      pCreateInfo->minImageCount);
    }

    auto& dt = DispatchTable::get();
    if (dt.CreateSwapchainKHR) {
        return dt.CreateSwapchainKHR(device, pCreateInfo, pAllocator, pSwapchain);
    }

    spdlog::error("vk_hooks: Real vkCreateSwapchainKHR is null, cannot forward call");
    return VK_ERROR_INITIALIZATION_FAILED;
}

} // namespace rtv_vr::vk
