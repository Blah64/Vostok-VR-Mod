#pragma once

#include <string_view>

namespace rtv_vr {

/// Compile-time constants for every configuration key used by the VR mod.
/// Keys are organized by section and referenced throughout the codebase to
/// avoid magic strings.
namespace ConfigKeys {

    // -- XR rendering --
    inline constexpr std::string_view XR_RENDER_SCALE  = "xr.render_scale";
    inline constexpr std::string_view XR_REFRESH_RATE  = "xr.refresh_rate";
    inline constexpr std::string_view XR_FOVEATION     = "xr.foveation";
    inline constexpr std::string_view XR_WORLD_SCALE   = "xr.world_scale";
    inline constexpr std::string_view XR_HEIGHT_OFFSET = "xr.height_offset";

    // -- Comfort options --
    inline constexpr std::string_view COMFORT_MOVEMENT_TYPE     = "comfort.movement_type";
    inline constexpr std::string_view COMFORT_TURN_TYPE         = "comfort.turn_type";
    inline constexpr std::string_view COMFORT_SNAP_DEGREES      = "comfort.snap_degrees";
    inline constexpr std::string_view COMFORT_SMOOTH_SPEED      = "comfort.smooth_speed";
    inline constexpr std::string_view COMFORT_VIGNETTE_ENABLED  = "comfort.vignette_enabled";
    inline constexpr std::string_view COMFORT_VIGNETTE_INTENSITY = "comfort.vignette_intensity";

    // -- Controller input --
    inline constexpr std::string_view CONTROLS_DOMINANT_HAND     = "controls.dominant_hand";
    inline constexpr std::string_view CONTROLS_DEADZONE          = "controls.deadzone";
    inline constexpr std::string_view CONTROLS_TRIGGER_THRESHOLD = "controls.trigger_threshold";
    inline constexpr std::string_view CONTROLS_GRIP_THRESHOLD    = "controls.grip_threshold";
    inline constexpr std::string_view CONTROLS_ACTION_MAP        = "controls.action_map";

    // -- Weapon handling --
    inline constexpr std::string_view WEAPONS_TWO_HAND          = "weapons.two_hand";
    inline constexpr std::string_view WEAPONS_TWO_HAND_DISTANCE = "weapons.two_hand_distance";
    inline constexpr std::string_view WEAPONS_GRIP_OFFSET       = "weapons.grip_offset";
    inline constexpr std::string_view WEAPONS_HAPTIC_INTENSITY  = "weapons.haptic_intensity";
    inline constexpr std::string_view WEAPONS_HAPTIC_DURATION   = "weapons.haptic_duration";

    // -- UI / HUD --
    inline constexpr std::string_view UI_ANCHOR_MODE   = "ui.anchor_mode";
    inline constexpr std::string_view UI_DISTANCE      = "ui.distance";
    inline constexpr std::string_view UI_SCALE         = "ui.scale";
    inline constexpr std::string_view UI_OPACITY       = "ui.opacity";
    inline constexpr std::string_view UI_LASER_VISIBLE = "ui.laser_visible";

    // -- Performance --
    inline constexpr std::string_view PERF_OVERLAY = "perf.overlay";
    inline constexpr std::string_view PERF_ASW     = "perf.asw";

    // -- Logging --
    inline constexpr std::string_view LOG_LEVEL = "log.level";
    inline constexpr std::string_view LOG_FILE  = "log.file";

} // namespace ConfigKeys
} // namespace rtv_vr
