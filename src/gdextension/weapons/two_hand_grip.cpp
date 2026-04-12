#include "two_hand_grip.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

TwoHandGrip::TwoHandGrip() = default;

Transform3D TwoHandGrip::compute_two_hand_transform(
    const Transform3D &p_primary,
    const Transform3D &p_secondary,
    const Transform3D &p_grip_offset) const {

    Vector3 primary_pos = p_primary.origin;
    Vector3 secondary_pos = p_secondary.origin;

    // Forward direction points from primary hand toward secondary hand.
    Vector3 forward = (secondary_pos - primary_pos).normalized();

    if (forward.length_squared() < 0.001f) {
        // Hands are too close; fall back to primary transform.
        return p_primary * p_grip_offset;
    }

    // Construct an orthonormal basis from the forward vector.
    Vector3 up_hint = Vector3(0.0f, 1.0f, 0.0f);
    Vector3 right = up_hint.cross(forward).normalized();

    if (right.length_squared() < 0.001f) {
        // Forward is nearly parallel to up; use alternative hint.
        up_hint = Vector3(0.0f, 0.0f, 1.0f);
        right = up_hint.cross(forward).normalized();
    }

    Vector3 up = forward.cross(right).normalized();

    Basis basis;
    basis.set_column(0, right);
    basis.set_column(1, up);
    basis.set_column(2, forward);

    Transform3D result(basis, primary_pos);
    return result * p_grip_offset;
}

void TwoHandGrip::update(double p_delta, XRController3D *p_primary, XRController3D *p_secondary) {
    if (p_primary == nullptr || p_secondary == nullptr) {
        is_active_ = false;
        blend_factor_ = 0.0f;
        return;
    }

    Vector3 primary_pos = p_primary->get_global_transform().origin;
    Vector3 secondary_pos = p_secondary->get_global_transform().origin;
    float distance = primary_pos.distance_to(secondary_pos);

    float delta_f = static_cast<float>(p_delta);

    if (distance < activation_distance_) {
        is_active_ = true;
        blend_factor_ = Math::lerp(blend_factor_, 1.0f, blend_speed_ * delta_f);
        blend_factor_ = Math::clamp(blend_factor_, 0.0f, 1.0f);
    } else if (distance > activation_distance_ * 1.5f) {
        is_active_ = false;
        blend_factor_ = Math::lerp(blend_factor_, 0.0f, blend_speed_ * delta_f);
        blend_factor_ = Math::clamp(blend_factor_, 0.0f, 1.0f);
    }
}

bool TwoHandGrip::is_active() const {
    return is_active_;
}

float TwoHandGrip::get_blend_factor() const {
    return blend_factor_;
}

void TwoHandGrip::set_activation_distance(float p_meters) {
    activation_distance_ = Math::max(p_meters, 0.01f);
}

float TwoHandGrip::get_activation_distance() const {
    return activation_distance_;
}

void TwoHandGrip::set_blend_speed(float p_speed) {
    blend_speed_ = Math::max(p_speed, 0.1f);
}

float TwoHandGrip::get_blend_speed() const {
    return blend_speed_;
}

void TwoHandGrip::_bind_methods() {
    ClassDB::bind_method(D_METHOD("compute_two_hand_transform", "primary", "secondary", "grip_offset"), &TwoHandGrip::compute_two_hand_transform);
    ClassDB::bind_method(D_METHOD("update", "delta", "primary", "secondary"), &TwoHandGrip::update);
    ClassDB::bind_method(D_METHOD("is_active"), &TwoHandGrip::is_active);
    ClassDB::bind_method(D_METHOD("get_blend_factor"), &TwoHandGrip::get_blend_factor);
    ClassDB::bind_method(D_METHOD("set_activation_distance", "meters"), &TwoHandGrip::set_activation_distance);
    ClassDB::bind_method(D_METHOD("get_activation_distance"), &TwoHandGrip::get_activation_distance);
    ClassDB::bind_method(D_METHOD("set_blend_speed", "speed"), &TwoHandGrip::set_blend_speed);
    ClassDB::bind_method(D_METHOD("get_blend_speed"), &TwoHandGrip::get_blend_speed);

    ADD_GROUP("Two Hand Grip", "two_hand_");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "two_hand_activation_distance", PROPERTY_HINT_RANGE, "0.01,1.0,0.01,suffix:m"), "set_activation_distance", "get_activation_distance");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "two_hand_blend_speed", PROPERTY_HINT_RANGE, "0.1,30.0,0.1"), "set_blend_speed", "get_blend_speed");
}

} // namespace rtv_vr
