#include "head_tracking.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/basis.hpp>

using namespace godot;

namespace rtv_vr {

HeadTracking::HeadTracking() {}

HeadTracking::~HeadTracking() {}

// ---------------------------------------------------------------------------
// update - Manage the head tracking to camera transform pipeline
// ---------------------------------------------------------------------------
void HeadTracking::update(double delta, XRCamera3D *camera, Node3D *game_camera) {
    if (!camera) {
        return;
    }

    if (!camera->is_inside_tree()) {
        return;
    }

    // Step 1: Read the XRCamera3D's global transform (head pose from VR runtime)
    Transform3D head_pose = camera->get_global_transform();

    // Step 2: Apply recenter offset if one has been requested
    if (needs_recenter_) {
        // Capture the current head position as the new origin offset
        recenter_offset_ = head_pose.get_origin();
        recenter_offset_.y = 0.0f; // Keep vertical as-is (floor-relative)
        needs_recenter_ = false;
        UtilityFunctions::print_rich("[color=cyan][RTV-VR] Head tracking recentered.[/color]");
    }

    // Apply recenter offset to the pose
    Vector3 adjusted_origin = head_pose.get_origin() - recenter_offset_;

    // Step 2b: Apply configured position offset
    adjusted_origin += position_offset_;

    // Step 2c: If positional tracking is disabled (seated mode), zero out
    // horizontal movement so only rotation is used
    if (!position_tracking_enabled_) {
        adjusted_origin.x = position_offset_.x;
        adjusted_origin.z = position_offset_.z;
        // Keep Y so the user's head height still works
    }

    // Step 2d: Apply rotation offset (e.g., for calibration)
    Basis rotation_adj;
    if (rotation_offset_degrees_.length_squared() > 0.0001f) {
        rotation_adj = Basis(Vector3(1, 0, 0), Math::deg_to_rad(rotation_offset_degrees_.x));
        rotation_adj = rotation_adj * Basis(Vector3(0, 1, 0), Math::deg_to_rad(rotation_offset_degrees_.y));
        rotation_adj = rotation_adj * Basis(Vector3(0, 0, 1), Math::deg_to_rad(rotation_offset_degrees_.z));
    }

    Transform3D final_pose;
    final_pose.basis = rotation_adj * head_pose.basis;
    final_pose.set_origin(adjusted_origin);

    // Cache for get_head_transform()
    cached_head_transform_ = final_pose;

    // Step 3: If a game camera reference exists, copy relevant aspects back
    // so that game logic (raycasts, AI awareness, audio listener) still works
    if (game_camera && game_camera->is_inside_tree()) {
        // Write the VR head pose into the game camera's global transform
        game_camera->set_global_transform(final_pose);
    }
}

// ---------------------------------------------------------------------------
// Position tracking toggle (seated vs. room-scale)
// ---------------------------------------------------------------------------
void HeadTracking::set_position_tracking(bool enabled) {
    position_tracking_enabled_ = enabled;
    UtilityFunctions::print_rich(
        String("[color=cyan][RTV-VR] Position tracking {0}.[/color]").format(
            Array::make(enabled ? "enabled" : "disabled")));
}

bool HeadTracking::get_position_tracking() const {
    return position_tracking_enabled_;
}

// ---------------------------------------------------------------------------
// recenter - Reset the tracking origin on next update
// ---------------------------------------------------------------------------
void HeadTracking::recenter() {
    needs_recenter_ = true;
}

// ---------------------------------------------------------------------------
// get_head_transform - Current head pose in world space
// ---------------------------------------------------------------------------
Transform3D HeadTracking::get_head_transform() const {
    return cached_head_transform_;
}

// ---------------------------------------------------------------------------
// Offsets
// ---------------------------------------------------------------------------
void HeadTracking::set_position_offset(const Vector3 &offset) {
    position_offset_ = offset;
}

Vector3 HeadTracking::get_position_offset() const {
    return position_offset_;
}

void HeadTracking::set_rotation_offset(const Vector3 &offset_degrees) {
    rotation_offset_degrees_ = offset_degrees;
}

Vector3 HeadTracking::get_rotation_offset() const {
    return rotation_offset_degrees_;
}

// ---------------------------------------------------------------------------
// _bind_methods
// ---------------------------------------------------------------------------
void HeadTracking::_bind_methods() {
    ClassDB::bind_method(D_METHOD("update", "delta", "camera", "game_camera"), &HeadTracking::update);

    ClassDB::bind_method(D_METHOD("set_position_tracking", "enabled"), &HeadTracking::set_position_tracking);
    ClassDB::bind_method(D_METHOD("get_position_tracking"), &HeadTracking::get_position_tracking);

    ClassDB::bind_method(D_METHOD("recenter"), &HeadTracking::recenter);
    ClassDB::bind_method(D_METHOD("get_head_transform"), &HeadTracking::get_head_transform);

    ClassDB::bind_method(D_METHOD("set_position_offset", "offset"), &HeadTracking::set_position_offset);
    ClassDB::bind_method(D_METHOD("get_position_offset"), &HeadTracking::get_position_offset);

    ClassDB::bind_method(D_METHOD("set_rotation_offset", "offset_degrees"), &HeadTracking::set_rotation_offset);
    ClassDB::bind_method(D_METHOD("get_rotation_offset"), &HeadTracking::get_rotation_offset);

    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "position_tracking"),
        "set_position_tracking", "get_position_tracking");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "position_offset"),
        "set_position_offset", "get_position_offset");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "rotation_offset"),
        "set_rotation_offset", "get_rotation_offset");
}

} // namespace rtv_vr
