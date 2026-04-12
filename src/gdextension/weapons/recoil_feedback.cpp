#include "recoil_feedback.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

RecoilFeedback::RecoilFeedback() = default;

void RecoilFeedback::fire(XRController3D *p_controller) {
    XRController3D *ctrl = (p_controller != nullptr) ? p_controller : controller_;
    if (ctrl == nullptr) {
        UtilityFunctions::push_warning("RecoilFeedback::fire: no controller set.");
        return;
    }

    // Trigger haptic pulse on the controller.
    // XRController3D uses: trigger_haptic_pulse(action_name, frequency, amplitude, duration_sec, delay_sec)
    double duration_sec = static_cast<double>(haptic_duration_ms_) / 1000.0;
    ctrl->trigger_haptic_pulse(
        StringName("haptic"),
        0.0,                                    // frequency (0 = default)
        static_cast<double>(haptic_intensity_), // amplitude
        duration_sec,                           // duration
        0.0                                     // delay
    );

    // Set visual recoil displacement.
    current_recoil_ = visual_recoil_amount_;

    // Store controller reference for future calls.
    if (controller_ == nullptr && p_controller != nullptr) {
        controller_ = p_controller;
    }
}

void RecoilFeedback::update(double p_delta) {
    if (current_recoil_ > 0.0f) {
        float delta_f = static_cast<float>(p_delta);
        current_recoil_ = Math::lerp(current_recoil_, 0.0f, visual_recoil_recovery_ * delta_f);

        // Snap to zero when very small.
        if (current_recoil_ < 0.0001f) {
            current_recoil_ = 0.0f;
        }
    }
}

Vector3 RecoilFeedback::get_recoil_offset() const {
    // Recoil is primarily along the negative Z axis (kickback toward the player).
    return Vector3(0.0f, 0.0f, -current_recoil_);
}

void RecoilFeedback::set_haptic_intensity(float p_intensity) {
    haptic_intensity_ = Math::clamp(p_intensity, 0.0f, 1.0f);
}

float RecoilFeedback::get_haptic_intensity() const {
    return haptic_intensity_;
}

void RecoilFeedback::set_haptic_duration(float p_ms) {
    haptic_duration_ms_ = Math::max(p_ms, 1.0f);
}

float RecoilFeedback::get_haptic_duration() const {
    return haptic_duration_ms_;
}

void RecoilFeedback::set_visual_recoil(float p_amount) {
    visual_recoil_amount_ = Math::max(p_amount, 0.0f);
}

float RecoilFeedback::get_visual_recoil() const {
    return visual_recoil_amount_;
}

void RecoilFeedback::set_visual_recoil_recovery(float p_speed) {
    visual_recoil_recovery_ = Math::max(p_speed, 0.1f);
}

float RecoilFeedback::get_visual_recoil_recovery() const {
    return visual_recoil_recovery_;
}

void RecoilFeedback::set_controller(XRController3D *p_controller) {
    controller_ = p_controller;
}

void RecoilFeedback::_bind_methods() {
    ClassDB::bind_method(D_METHOD("fire", "controller"), &RecoilFeedback::fire, DEFVAL(nullptr));
    ClassDB::bind_method(D_METHOD("update", "delta"), &RecoilFeedback::update);
    ClassDB::bind_method(D_METHOD("get_recoil_offset"), &RecoilFeedback::get_recoil_offset);

    ClassDB::bind_method(D_METHOD("set_haptic_intensity", "intensity"), &RecoilFeedback::set_haptic_intensity);
    ClassDB::bind_method(D_METHOD("get_haptic_intensity"), &RecoilFeedback::get_haptic_intensity);
    ClassDB::bind_method(D_METHOD("set_haptic_duration", "ms"), &RecoilFeedback::set_haptic_duration);
    ClassDB::bind_method(D_METHOD("get_haptic_duration"), &RecoilFeedback::get_haptic_duration);
    ClassDB::bind_method(D_METHOD("set_visual_recoil", "amount"), &RecoilFeedback::set_visual_recoil);
    ClassDB::bind_method(D_METHOD("get_visual_recoil"), &RecoilFeedback::get_visual_recoil);
    ClassDB::bind_method(D_METHOD("set_visual_recoil_recovery", "speed"), &RecoilFeedback::set_visual_recoil_recovery);
    ClassDB::bind_method(D_METHOD("get_visual_recoil_recovery"), &RecoilFeedback::get_visual_recoil_recovery);
    ClassDB::bind_method(D_METHOD("set_controller", "controller"), &RecoilFeedback::set_controller);

    ADD_GROUP("Haptics", "haptic_");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "haptic_intensity", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_haptic_intensity", "get_haptic_intensity");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "haptic_duration_ms", PROPERTY_HINT_RANGE, "1.0,500.0,1.0,suffix:ms"), "set_haptic_duration", "get_haptic_duration");

    ADD_GROUP("Visual Recoil", "visual_recoil_");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "visual_recoil_amount", PROPERTY_HINT_RANGE, "0.0,0.2,0.001,suffix:m"), "set_visual_recoil", "get_visual_recoil");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "visual_recoil_recovery", PROPERTY_HINT_RANGE, "0.1,50.0,0.1"), "set_visual_recoil_recovery", "get_visual_recoil_recovery");
}

} // namespace rtv_vr
