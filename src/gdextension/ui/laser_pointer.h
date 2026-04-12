#ifndef RTV_VR_LASER_POINTER_H
#define RTV_VR_LASER_POINTER_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace rtv_vr {

class LaserPointer : public godot::Node3D {
    GDCLASS(LaserPointer, godot::Node3D)

public:
    LaserPointer();
    ~LaserPointer() override;

    void initialize(godot::XRController3D *p_controller);

    // Godot lifecycle
    void _process(double p_delta) override;

    // Setters / getters
    void set_visible(bool p_visible);
    bool get_visible() const;

    void set_color(const godot::Color &p_color);
    godot::Color get_color() const;

    void set_max_length(float p_meters);
    float get_max_length() const;

    godot::Dictionary get_hit_info() const;

protected:
    static void _bind_methods();

private:
    void update_ray_mesh(float p_length);

    godot::MeshInstance3D *ray_mesh_ = nullptr;
    godot::Node3D *hit_marker_ = nullptr;
    float max_length_ = 5.0f;
    bool visible_ = true;
    godot::XRController3D *controller_ = nullptr;
    godot::Color ray_color_ = godot::Color(0.2f, 0.6f, 1.0f, 0.8f);
    godot::Dictionary last_hit_info_;
};

} // namespace rtv_vr

#endif // RTV_VR_LASER_POINTER_H
