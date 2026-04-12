#include "hud_anchor.h"

#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

HUDAnchor::HUDAnchor() = default;
HUDAnchor::~HUDAnchor() = default;

void HUDAnchor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_references", "camera", "left_controller", "right_controller"),
            &HUDAnchor::set_references);

    ClassDB::bind_method(D_METHOD("set_anchor_type", "type"), &HUDAnchor::set_anchor_type);
    ClassDB::bind_method(D_METHOD("get_anchor_type"), &HUDAnchor::get_anchor_type);

    ClassDB::bind_method(D_METHOD("set_offset", "offset"), &HUDAnchor::set_offset);
    ClassDB::bind_method(D_METHOD("get_offset"), &HUDAnchor::get_offset);

    ClassDB::bind_method(D_METHOD("set_follow_speed", "speed"), &HUDAnchor::set_follow_speed);
    ClassDB::bind_method(D_METHOD("get_follow_speed"), &HUDAnchor::get_follow_speed);

    // Properties.
    ADD_PROPERTY(PropertyInfo(Variant::INT, "anchor_type", PROPERTY_HINT_ENUM,
                     "Head,LeftWrist,RightWrist,World,Belt"),
            "set_anchor_type", "get_anchor_type");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "offset"),
            "set_offset", "get_offset");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "follow_speed", PROPERTY_HINT_RANGE, "1.0,20.0,0.5"),
            "set_follow_speed", "get_follow_speed");

    // Enum constants.
    BIND_ENUM_CONSTANT(ANCHOR_HEAD);
    BIND_ENUM_CONSTANT(ANCHOR_LEFT_WRIST);
    BIND_ENUM_CONSTANT(ANCHOR_RIGHT_WRIST);
    BIND_ENUM_CONSTANT(ANCHOR_WORLD);
    BIND_ENUM_CONSTANT(ANCHOR_BELT);

    // Signals.
    ADD_SIGNAL(MethodInfo("anchor_type_changed", PropertyInfo(Variant::INT, "new_type")));
}

void HUDAnchor::set_references(XRCamera3D *p_camera,
                               XRController3D *p_left,
                               XRController3D *p_right) {
    camera_ = p_camera;
    left_controller_ = p_left;
    right_controller_ = p_right;
}

void HUDAnchor::set_anchor_type(AnchorType p_type) {
    if (anchor_type_ != p_type) {
        anchor_type_ = p_type;
        first_frame_ = true;
        emit_signal("anchor_type_changed", (int)p_type);
    }
}

HUDAnchor::AnchorType HUDAnchor::get_anchor_type() const {
    return anchor_type_;
}

void HUDAnchor::set_offset(const Vector3 &p_offset) {
    offset_ = p_offset;
}

Vector3 HUDAnchor::get_offset() const {
    return offset_;
}

void HUDAnchor::set_follow_speed(float p_speed) {
    follow_speed_ = CLAMP(p_speed, 1.0f, 20.0f);
}

float HUDAnchor::get_follow_speed() const {
    return follow_speed_;
}

void HUDAnchor::_process(double p_delta) {
    switch (anchor_type_) {
        case ANCHOR_HEAD:
            update_head(p_delta);
            break;
        case ANCHOR_LEFT_WRIST:
            update_wrist(left_controller_, p_delta);
            break;
        case ANCHOR_RIGHT_WRIST:
            update_wrist(right_controller_, p_delta);
            break;
        case ANCHOR_WORLD:
            // Static -- no updates.
            break;
        case ANCHOR_BELT:
            update_belt(p_delta);
            break;
    }
}

void HUDAnchor::update_head(double p_delta) {
    if (!camera_) {
        return;
    }

    Transform3D cam_xform = camera_->get_global_transform();
    // Compute target in camera-local space then convert to global.
    Vector3 target_pos = cam_xform.xform(offset_);

    Transform3D target;
    target.origin = target_pos;
    // Face the same direction as the camera.
    target.basis = cam_xform.basis;

    if (first_frame_) {
        set_global_transform(target);
        target_transform_ = target;
        first_frame_ = false;
        return;
    }

    target_transform_ = target;

    // Smooth follow.
    float t = CLAMP((float)(follow_speed_ * p_delta), 0.0f, 1.0f);
    Transform3D current = get_global_transform();
    current.origin = current.origin.lerp(target_transform_.origin, t);

    Quaternion cur_q(current.basis);
    Quaternion tgt_q(target_transform_.basis);
    current.basis = Basis(cur_q.slerp(tgt_q, t));

    set_global_transform(current);
}

void HUDAnchor::update_wrist(XRController3D *p_controller, double p_delta) {
    if (!p_controller) {
        // Fallback to head.
        update_head(p_delta);
        return;
    }

    Transform3D ctrl_xform = p_controller->get_global_transform();
    // Offset slightly above and in front of the wrist.
    Vector3 up = ctrl_xform.basis.get_column(1).normalized();
    Vector3 forward = -ctrl_xform.basis.get_column(2).normalized();
    Vector3 wrist_offset = up * 0.1f + forward * 0.05f;

    Transform3D target;
    target.origin = ctrl_xform.origin + wrist_offset;
    // Tilt toward the user: rotate around controller's local X axis.
    target.basis = ctrl_xform.basis.rotated(
            ctrl_xform.basis.get_column(0).normalized(),
            -Math::deg_to_rad(30.0f));

    if (first_frame_) {
        set_global_transform(target);
        first_frame_ = false;
        return;
    }

    // Smooth follow for wrist (faster than head to feel responsive).
    float t = CLAMP((float)(follow_speed_ * 1.5f * p_delta), 0.0f, 1.0f);
    Transform3D current = get_global_transform();
    current.origin = current.origin.lerp(target.origin, t);
    Quaternion cur_q(current.basis);
    Quaternion tgt_q(target.basis);
    current.basis = Basis(cur_q.slerp(tgt_q, t));

    set_global_transform(current);
}

void HUDAnchor::update_belt(double p_delta) {
    if (!camera_) {
        return;
    }

    Transform3D cam_xform = camera_->get_global_transform();

    // Belt position: at the camera height minus ~0.5m, forward offset.
    // Only follow the yaw rotation (not pitch/roll) for stability.
    Vector3 cam_forward = -cam_xform.basis.get_column(2);
    cam_forward.y = 0.0f;
    cam_forward = cam_forward.normalized();

    Vector3 target_pos = cam_xform.origin;
    target_pos.y -= 0.5f;
    target_pos += cam_forward * Math::abs(offset_.z);

    // Build a basis that faces the camera horizontally.
    Vector3 up = Vector3(0.0f, 1.0f, 0.0f);
    Vector3 right = up.cross(cam_forward).normalized();
    Basis target_basis(right, up, -cam_forward);
    // Slight forward tilt so it's easier to look down at.
    target_basis = target_basis.rotated(right, Math::deg_to_rad(20.0f));

    Transform3D target;
    target.origin = target_pos;
    target.basis = target_basis;

    if (first_frame_) {
        set_global_transform(target);
        target_transform_ = target;
        first_frame_ = false;
        return;
    }

    target_transform_ = target;

    // Heavy smoothing for belt so it doesn't jiggle.
    float belt_speed = follow_speed_ * 0.4f;
    float t = CLAMP((float)(belt_speed * p_delta), 0.0f, 1.0f);
    Transform3D current = get_global_transform();
    current.origin = current.origin.lerp(target_transform_.origin, t);
    Quaternion cur_q(current.basis);
    Quaternion tgt_q(target_transform_.basis);
    current.basis = Basis(cur_q.slerp(tgt_q, t));

    set_global_transform(current);
}

} // namespace rtv_vr
