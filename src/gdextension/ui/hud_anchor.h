#ifndef RTV_VR_HUD_ANCHOR_H
#define RTV_VR_HUD_ANCHOR_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/xr_camera3d.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace rtv_vr {

class HUDAnchor : public godot::Node3D {
    GDCLASS(HUDAnchor, godot::Node3D)

public:
    enum AnchorType {
        ANCHOR_HEAD,
        ANCHOR_LEFT_WRIST,
        ANCHOR_RIGHT_WRIST,
        ANCHOR_WORLD,
        ANCHOR_BELT,
    };

    HUDAnchor();
    ~HUDAnchor() override;

    void set_references(godot::XRCamera3D *p_camera,
                        godot::XRController3D *p_left,
                        godot::XRController3D *p_right);

    void set_anchor_type(AnchorType p_type);
    AnchorType get_anchor_type() const;

    void set_offset(const godot::Vector3 &p_offset);
    godot::Vector3 get_offset() const;

    void set_follow_speed(float p_speed);
    float get_follow_speed() const;

    // Godot lifecycle
    void _process(double p_delta) override;

protected:
    static void _bind_methods();

private:
    void update_head(double p_delta);
    void update_wrist(godot::XRController3D *p_controller, double p_delta);
    void update_belt(double p_delta);

    AnchorType anchor_type_ = ANCHOR_HEAD;
    godot::Vector3 offset_ = godot::Vector3(0.0f, 0.0f, -1.5f);
    float follow_speed_ = 5.0f;
    godot::Transform3D target_transform_;
    bool first_frame_ = true;

    godot::XRCamera3D *camera_ = nullptr;
    godot::XRController3D *left_controller_ = nullptr;
    godot::XRController3D *right_controller_ = nullptr;
};

} // namespace rtv_vr

VARIANT_ENUM_CAST(rtv_vr::HUDAnchor::AnchorType)

#endif // RTV_VR_HUD_ANCHOR_H
