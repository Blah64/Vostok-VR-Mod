#ifndef RTV_VR_TWO_HAND_GRIP_H
#define RTV_VR_TWO_HAND_GRIP_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace rtv_vr {

class TwoHandGrip : public godot::RefCounted {
    GDCLASS(TwoHandGrip, godot::RefCounted)

public:
    TwoHandGrip();
    ~TwoHandGrip() override = default;

    /// Computes the weapon transform when using a two-handed grip.
    godot::Transform3D compute_two_hand_transform(
        const godot::Transform3D &p_primary,
        const godot::Transform3D &p_secondary,
        const godot::Transform3D &p_grip_offset) const;

    /// Updates the activation state and blend factor based on hand distances.
    void update(double p_delta, godot::XRController3D *p_primary, godot::XRController3D *p_secondary);

    /// Returns true if two-hand grip is currently active.
    bool is_active() const;

    /// Returns blend factor (0.0 = single hand, 1.0 = full two-hand).
    float get_blend_factor() const;

    /// Set activation distance in meters.
    void set_activation_distance(float p_meters);

    /// Get activation distance.
    float get_activation_distance() const;

    /// Set blend speed.
    void set_blend_speed(float p_speed);

    /// Get blend speed.
    float get_blend_speed() const;

protected:
    static void _bind_methods();

private:
    float activation_distance_ = 0.15f;
    bool is_active_ = false;
    float blend_factor_ = 0.0f;
    float blend_speed_ = 8.0f;
};

} // namespace rtv_vr

#endif // RTV_VR_TWO_HAND_GRIP_H
