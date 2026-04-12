#include "hud_reprojector.h"

#include <spdlog/spdlog.h>

#include <mutex>
#include <unordered_set>

namespace rtv_vr::vk::hud_reprojector {

namespace {
    std::mutex                       g_mutex;
    std::unordered_set<VkRenderPass> g_hud_passes;
} // anonymous namespace

bool initialize() {
    std::lock_guard lock(g_mutex);
    g_hud_passes.clear();
    spdlog::info("HUD reprojector initialized (stub)");
    return true;
}

void shutdown() {
    std::lock_guard lock(g_mutex);
    g_hud_passes.clear();
    spdlog::info("HUD reprojector shut down");
}

void process_frame() {
    // No-op stub. Future implementation will:
    // 1. Capture HUD render pass output texture
    // 2. Reproject onto a world-space quad
    // 3. Composite into each VR eye view
}

void mark_hud_render_pass(VkRenderPass pass) {
    std::lock_guard lock(g_mutex);
    auto [it, inserted] = g_hud_passes.insert(pass);
    if (inserted) {
        spdlog::debug("HUD reprojector: Marked render pass {} as HUD",
                       reinterpret_cast<void*>(pass));
    }
}

bool is_hud_render_pass(VkRenderPass pass) {
    std::lock_guard lock(g_mutex);
    return g_hud_passes.count(pass) > 0;
}

} // namespace rtv_vr::vk::hud_reprojector
