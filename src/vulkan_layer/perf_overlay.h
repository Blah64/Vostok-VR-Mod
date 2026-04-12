#pragma once

namespace rtv_vr::vk::perf_overlay {

/// Initialize the performance overlay subsystem.
bool initialize();

/// Shut down and release resources.
void shutdown();

/// Enable or disable the overlay display.
void set_enabled(bool enabled);

/// Query whether the overlay is currently enabled.
bool is_enabled();

/// Called each time a frame is submitted to the GPU queue.
/// Records timing data for FPS / frame time calculations.
void on_frame_submitted();

/// Average frames per second over the last 120 samples.
float get_fps();

/// Average frame time in milliseconds over the last 120 samples.
float get_frame_time_ms();

/// Maximum frame time in milliseconds over the last 120 samples
/// (useful for stutter/jank detection).
float get_frame_time_max_ms();

} // namespace rtv_vr::vk::perf_overlay
