#include "camera_override.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

CameraOverride::CameraOverride() {}

CameraOverride::~CameraOverride() {
    // Do not free Godot nodes here; the scene tree owns them.
}

// ---------------------------------------------------------------------------
// Recursive search - mirrors SceneInspector-style depth-first traversal
// ---------------------------------------------------------------------------
Camera3D *CameraOverride::find_camera3d_recursive(Node *node) const {
    if (!node) {
        return nullptr;
    }

    Camera3D *cam = Object::cast_to<Camera3D>(node);
    if (cam) {
        return cam;
    }

    int child_count = node->get_child_count();
    for (int i = 0; i < child_count; ++i) {
        Camera3D *result = find_camera3d_recursive(node->get_child(i));
        if (result) {
            return result;
        }
    }
    return nullptr;
}

// ---------------------------------------------------------------------------
// install - Replace the game's Camera3D with an XR camera rig
// ---------------------------------------------------------------------------
bool CameraOverride::install(Node *scene_root) {
    if (installed_) {
        UtilityFunctions::print_rich("[color=yellow][RTV-VR] CameraOverride already installed, skipping.[/color]");
        return true;
    }

    if (!scene_root) {
        UtilityFunctions::print_rich("[color=red][RTV-VR] CameraOverride::install - scene_root is null.[/color]");
        return false;
    }

    // Step 1: Find the first Camera3D in the scene tree
    original_camera_ = find_camera3d_recursive(scene_root);
    if (!original_camera_) {
        UtilityFunctions::print_rich("[color=red][RTV-VR] CameraOverride::install - No Camera3D found in scene.[/color]");
        return false;
    }

    UtilityFunctions::print_rich(
        String("[color=green][RTV-VR] Found Camera3D: {0}[/color]").format(
            Array::make(original_camera_->get_path())));

    // Step 2: Get the camera's parent and position
    original_camera_parent_ = original_camera_->get_parent();
    if (!original_camera_parent_) {
        UtilityFunctions::print_rich("[color=red][RTV-VR] CameraOverride::install - Camera3D has no parent.[/color]");
        original_camera_ = nullptr;
        return false;
    }

    original_camera_index_ = original_camera_->get_index();
    original_camera_transform_ = original_camera_->get_transform();

    // Step 3: Create XROrigin3D
    xr_origin_ = memnew(XROrigin3D);
    xr_origin_->set_name("RTV_XROrigin3D");

    // Step 4: Create XRCamera3D
    xr_camera_ = memnew(XRCamera3D);
    xr_camera_->set_name("RTV_XRCamera3D");

    // Step 5: Insert XROrigin3D where Camera3D was
    original_camera_parent_->add_child(xr_origin_);
    original_camera_parent_->move_child(xr_origin_, original_camera_index_);

    // Step 6: Add XRCamera3D as child of XROrigin3D
    xr_origin_->add_child(xr_camera_);

    // Step 7: Copy the Camera3D's transform to XROrigin3D
    xr_origin_->set_transform(original_camera_transform_);

    // Apply current settings
    xr_origin_->set_world_scale(world_scale_);
    if (height_offset_ != 0.0f) {
        Transform3D t = xr_origin_->get_transform();
        Vector3 origin = t.get_origin();
        origin.y += height_offset_;
        t.set_origin(origin);
        xr_origin_->set_transform(t);
    }

    // Step 8/9: Disable the original camera (hide it, don't delete)
    original_camera_->set_current(false);
    original_camera_->set_visible(false);

    // Step 10: Make XRCamera3D current
    xr_camera_->set_current(true);

    installed_ = true;
    UtilityFunctions::print_rich("[color=green][RTV-VR] XR camera rig installed successfully.[/color]");
    return true;
}

// ---------------------------------------------------------------------------
// uninstall - Reverse the camera replacement
// ---------------------------------------------------------------------------
void CameraOverride::uninstall() {
    if (!installed_) {
        UtilityFunctions::print_rich("[color=yellow][RTV-VR] CameraOverride not installed, nothing to uninstall.[/color]");
        return;
    }

    // Restore original camera
    if (original_camera_ && original_camera_->is_inside_tree()) {
        original_camera_->set_visible(true);
        original_camera_->set_current(true);
    }

    // Remove XR rig from the tree and free
    if (xr_camera_ && xr_camera_->is_inside_tree()) {
        xr_origin_->remove_child(xr_camera_);
    }
    if (xr_origin_ && xr_origin_->is_inside_tree()) {
        original_camera_parent_->remove_child(xr_origin_);
    }

    if (xr_camera_) {
        xr_camera_->queue_free();
        xr_camera_ = nullptr;
    }
    if (xr_origin_) {
        xr_origin_->queue_free();
        xr_origin_ = nullptr;
    }

    original_camera_ = nullptr;
    original_camera_parent_ = nullptr;
    original_camera_index_ = -1;
    installed_ = false;

    UtilityFunctions::print_rich("[color=green][RTV-VR] XR camera rig uninstalled, original camera restored.[/color]");
}

// ---------------------------------------------------------------------------
// World scale
// ---------------------------------------------------------------------------
void CameraOverride::set_world_scale(float scale) {
    world_scale_ = scale;
    if (xr_origin_) {
        xr_origin_->set_world_scale(scale);
        UtilityFunctions::print_rich(
            String("[color=cyan][RTV-VR] World scale set to {0}[/color]").format(
                Array::make(scale)));
    }
}

float CameraOverride::get_world_scale() const {
    return world_scale_;
}

// ---------------------------------------------------------------------------
// Height offset
// ---------------------------------------------------------------------------
void CameraOverride::set_height_offset(float meters) {
    if (!xr_origin_) {
        height_offset_ = meters;
        return;
    }

    // Remove old offset, apply new
    Transform3D t = xr_origin_->get_transform();
    Vector3 origin = t.get_origin();
    origin.y -= height_offset_;
    origin.y += meters;
    t.set_origin(origin);
    xr_origin_->set_transform(t);

    height_offset_ = meters;
}

float CameraOverride::get_height_offset() const {
    return height_offset_;
}

// ---------------------------------------------------------------------------
// sync_origin_to_game_camera - Keep XR origin in sync with game locomotion
// ---------------------------------------------------------------------------
void CameraOverride::sync_origin_to_game_camera() {
    if (!installed_ || !xr_origin_ || !original_camera_) {
        return;
    }

    if (!original_camera_->is_inside_tree()) {
        return;
    }

    // The game's scripts may move the original camera (or its parent chain)
    // for locomotion. We mirror that position onto the XR origin so the
    // player moves through the world correctly.
    Transform3D game_transform = original_camera_->get_global_transform();
    Transform3D xr_transform = xr_origin_->get_global_transform();

    // Copy position from game camera; keep XR orientation (head tracking owns it)
    Vector3 game_pos = game_transform.get_origin();
    game_pos.y += height_offset_;

    Transform3D new_transform = xr_transform;
    new_transform.set_origin(game_pos);
    xr_origin_->set_global_transform(new_transform);
}

// ---------------------------------------------------------------------------
// Getters
// ---------------------------------------------------------------------------
XROrigin3D *CameraOverride::get_xr_origin() const {
    return xr_origin_;
}

XRCamera3D *CameraOverride::get_xr_camera() const {
    return xr_camera_;
}

// ---------------------------------------------------------------------------
// _bind_methods
// ---------------------------------------------------------------------------
void CameraOverride::_bind_methods() {
    ClassDB::bind_method(D_METHOD("install", "scene_root"), &CameraOverride::install);
    ClassDB::bind_method(D_METHOD("uninstall"), &CameraOverride::uninstall);

    ClassDB::bind_method(D_METHOD("set_world_scale", "scale"), &CameraOverride::set_world_scale);
    ClassDB::bind_method(D_METHOD("get_world_scale"), &CameraOverride::get_world_scale);

    ClassDB::bind_method(D_METHOD("set_height_offset", "meters"), &CameraOverride::set_height_offset);
    ClassDB::bind_method(D_METHOD("get_height_offset"), &CameraOverride::get_height_offset);

    ClassDB::bind_method(D_METHOD("sync_origin_to_game_camera"), &CameraOverride::sync_origin_to_game_camera);

    ClassDB::bind_method(D_METHOD("get_xr_origin"), &CameraOverride::get_xr_origin);
    ClassDB::bind_method(D_METHOD("get_xr_camera"), &CameraOverride::get_xr_camera);

    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "world_scale", PROPERTY_HINT_RANGE, "0.1,100.0,0.1"),
        "set_world_scale", "get_world_scale");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "height_offset", PROPERTY_HINT_RANGE, "-5.0,5.0,0.01"),
        "set_height_offset", "get_height_offset");
}

} // namespace rtv_vr
