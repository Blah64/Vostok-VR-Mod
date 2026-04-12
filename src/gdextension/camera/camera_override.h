#ifndef RTV_VR_CAMERA_OVERRIDE_H
#define RTV_VR_CAMERA_OVERRIDE_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/xr_origin3d.hpp>
#include <godot_cpp/classes/xr_camera3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace rtv_vr {

class CameraOverride : public godot::Node3D {
    GDCLASS(CameraOverride, godot::Node3D)

public:
    CameraOverride();
    ~CameraOverride();

    bool install(godot::Node *scene_root);
    void uninstall();

    void set_world_scale(float scale);
    float get_world_scale() const;

    void set_height_offset(float meters);
    float get_height_offset() const;

    void sync_origin_to_game_camera();

    godot::XROrigin3D *get_xr_origin() const;
    godot::XRCamera3D *get_xr_camera() const;

protected:
    static void _bind_methods();

private:
    godot::Camera3D *find_camera3d_recursive(godot::Node *node) const;

    godot::XROrigin3D *xr_origin_ = nullptr;
    godot::XRCamera3D *xr_camera_ = nullptr;
    godot::Camera3D *original_camera_ = nullptr;
    godot::Node *original_camera_parent_ = nullptr;
    int original_camera_index_ = -1;
    godot::Transform3D original_camera_transform_;

    float world_scale_ = 1.0f;
    float height_offset_ = 0.0f;
    bool installed_ = false;
};

} // namespace rtv_vr

#endif // RTV_VR_CAMERA_OVERRIDE_H
