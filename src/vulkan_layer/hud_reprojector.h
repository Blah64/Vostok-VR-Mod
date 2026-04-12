#pragma once

#include <vulkan/vulkan.h>

namespace rtv_vr::vk {

/// Stub implementation for HUD reprojection into VR eye views.
/// Will eventually extract the 2D HUD render pass output and composite it
/// onto a world-space quad visible in the headset.
namespace hud_reprojector {

bool initialize();
void shutdown();

/// Called once per frame to perform any HUD reprojection work.
void process_frame();

/// Mark a VkRenderPass as one that renders HUD elements.
void mark_hud_render_pass(VkRenderPass pass);

/// Check whether the given render pass was previously marked as a HUD pass.
bool is_hud_render_pass(VkRenderPass pass);

} // namespace hud_reprojector
} // namespace rtv_vr::vk
