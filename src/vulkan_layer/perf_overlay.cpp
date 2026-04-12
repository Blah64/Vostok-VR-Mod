#include "perf_overlay.h"

#include <spdlog/spdlog.h>

#include <array>
#include <atomic>
#include <chrono>
#include <mutex>

namespace rtv_vr::vk::perf_overlay {

namespace {

constexpr size_t kBufferSize = 120;

std::mutex  g_mutex;
bool        g_enabled = false;

// Circular buffer of frame times in milliseconds.
std::array<float, kBufferSize> g_frame_times{};
size_t  g_write_index = 0;
size_t  g_sample_count = 0;

using Clock = std::chrono::steady_clock;
Clock::time_point g_last_frame_time{};

} // anonymous namespace

bool initialize() {
    std::lock_guard lock(g_mutex);
    g_frame_times.fill(0.0f);
    g_write_index  = 0;
    g_sample_count = 0;
    g_last_frame_time = Clock::time_point{};
    g_enabled = false;
    spdlog::info("perf_overlay: Initialized");
    return true;
}

void shutdown() {
    std::lock_guard lock(g_mutex);
    g_enabled = false;
    g_frame_times.fill(0.0f);
    g_write_index  = 0;
    g_sample_count = 0;
    spdlog::info("perf_overlay: Shut down");
}

void set_enabled(bool enabled) {
    std::lock_guard lock(g_mutex);
    if (g_enabled != enabled) {
        g_enabled = enabled;
        spdlog::info("perf_overlay: {}", enabled ? "Enabled" : "Disabled");
    }
}

bool is_enabled() {
    std::lock_guard lock(g_mutex);
    return g_enabled;
}

void on_frame_submitted() {
    std::lock_guard lock(g_mutex);

    auto now = Clock::now();

    // Skip the very first sample (no delta yet).
    if (g_last_frame_time != Clock::time_point{}) {
        float dt_ms = std::chrono::duration<float, std::milli>(
                          now - g_last_frame_time)
                          .count();

        g_frame_times[g_write_index] = dt_ms;
        g_write_index = (g_write_index + 1) % kBufferSize;
        if (g_sample_count < kBufferSize) {
            ++g_sample_count;
        }
    }

    g_last_frame_time = now;
}

float get_fps() {
    std::lock_guard lock(g_mutex);
    if (g_sample_count == 0) {
        return 0.0f;
    }

    float total_ms = 0.0f;
    for (size_t i = 0; i < g_sample_count; ++i) {
        total_ms += g_frame_times[i];
    }

    float avg_ms = total_ms / static_cast<float>(g_sample_count);
    if (avg_ms <= 0.0f) {
        return 0.0f;
    }

    return 1000.0f / avg_ms;
}

float get_frame_time_ms() {
    std::lock_guard lock(g_mutex);
    if (g_sample_count == 0) {
        return 0.0f;
    }

    float total_ms = 0.0f;
    for (size_t i = 0; i < g_sample_count; ++i) {
        total_ms += g_frame_times[i];
    }

    return total_ms / static_cast<float>(g_sample_count);
}

float get_frame_time_max_ms() {
    std::lock_guard lock(g_mutex);
    if (g_sample_count == 0) {
        return 0.0f;
    }

    float max_ms = 0.0f;
    for (size_t i = 0; i < g_sample_count; ++i) {
        if (g_frame_times[i] > max_ms) {
            max_ms = g_frame_times[i];
        }
    }

    return max_ms;
}

} // namespace rtv_vr::vk::perf_overlay
