#include "haptics.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

Haptics::Haptics() = default;
Haptics::~Haptics() = default;

void Haptics::trigger_haptic(XRController3D *p_controller, float p_intensity, float p_duration_sec) {
    ERR_FAIL_NULL_MSG(p_controller,
            "Haptics: Cannot trigger haptic on null controller.");

    p_intensity = CLAMP(p_intensity, 0.0f, 1.0f);
    p_duration_sec = MAX(p_duration_sec, 0.0f);

    p_controller->trigger_haptic_pulse(
            String("haptic"),      // action name
            0.0,                   // frequency (0 = default)
            p_intensity,           // amplitude
            p_duration_sec,        // duration
            0.0                    // delay
    );
}

void Haptics::pulse_left(float p_intensity, float p_duration) {
    if (left_controller_ == nullptr) {
        UtilityFunctions::push_warning("Haptics: Left controller not set.");
        return;
    }
    trigger_haptic(left_controller_, p_intensity, p_duration);
}

void Haptics::pulse_right(float p_intensity, float p_duration) {
    if (right_controller_ == nullptr) {
        UtilityFunctions::push_warning("Haptics: Right controller not set.");
        return;
    }
    trigger_haptic(right_controller_, p_intensity, p_duration);
}

void Haptics::set_controllers(XRController3D *p_left, XRController3D *p_right) {
    left_controller_ = p_left;
    right_controller_ = p_right;
}

void Haptics::stop_all() {
    // Trigger a zero-intensity, zero-duration pulse to cancel ongoing haptics.
    if (left_controller_ != nullptr) {
        trigger_haptic(left_controller_, 0.0f, 0.0f);
    }
    if (right_controller_ != nullptr) {
        trigger_haptic(right_controller_, 0.0f, 0.0f);
    }
}

void Haptics::_bind_methods() {
    ClassDB::bind_method(D_METHOD("trigger_haptic", "controller", "intensity", "duration_sec"),
            &Haptics::trigger_haptic);
    ClassDB::bind_method(D_METHOD("pulse_left", "intensity", "duration"),
            &Haptics::pulse_left);
    ClassDB::bind_method(D_METHOD("pulse_right", "intensity", "duration"),
            &Haptics::pulse_right);
    ClassDB::bind_method(D_METHOD("set_controllers", "left", "right"),
            &Haptics::set_controllers);
    ClassDB::bind_method(D_METHOD("stop_all"), &Haptics::stop_all);
}

} // namespace rtv_vr
