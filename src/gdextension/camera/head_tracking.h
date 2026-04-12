#ifndef RTV_VR_HEAD_TRACKING_H
#define RTV_VR_HEAD_TRACKING_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/xr_camera3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace rtv_vr {

class HeadTracking : public godot::RefCounted {
    GDCLASS(HeadTracking, godot::RefCounted)

public:
    HeadTracking();
    ~HeadTracking();

    void update(double delta, godot::XRCamera3D *camera, godot::Node3D *game_camera);

    void set_position_tracking(bool enabled);
    bool get_position_tracking() const;

    void recenter();

    godot::Transform3D get_head_transform() const;

    void set_position_offset(const godot::Vector3 &offset);
    godot::Vector3 get_position_offset() const;

    void set_rotation_offset(const godot::Vector3 &offset_degrees);
    godot::Vector3 get_rotation_offset() const;

protected:
    static void _bind_methods();

private:
    bool position_tracking_enabled_ = true;
    godot::Vector3 position_offset_;
    godot::Vector3 rotation_offset_degrees_;
    godot::Transform3D cached_head_transform_;
    godot::Vector3 recenter_offset_;
    bool needs_recenter_ = false;
};

} // namespace rtv_vr

#endif // RTV_VR_HEAD_TRACKING_H
