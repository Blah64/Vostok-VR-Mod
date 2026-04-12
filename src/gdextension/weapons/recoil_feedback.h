#ifndef RTV_VR_RECOIL_FEEDBACK_H
#define RTV_VR_RECOIL_FEEDBACK_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace rtv_vr {

class RecoilFeedback : public godot::RefCounted {
    GDCLASS(RecoilFeedback, godot::RefCounted)

public:
    RecoilFeedback();
    ~RecoilFeedback() override = default;

    /// Trigger fire feedback (haptic + visual recoil).
    void fire(godot::XRController3D *p_controller);

    /// Update recoil decay each frame.
    void update(double p_delta);

    /// Returns the current recoil offset vector (primarily Z-axis kickback).
    godot::Vector3 get_recoil_offset() const;

    /// Set haptic intensity (0.0 - 1.0).
    void set_haptic_intensity(float p_intensity);
    float get_haptic_intensity() const;

    /// Set haptic duration in milliseconds.
    void set_haptic_duration(float p_ms);
    float get_haptic_duration() const;

    /// Set visual recoil amount in meters.
    void set_visual_recoil(float p_amount);
    float get_visual_recoil() const;

    /// Set visual recoil recovery speed.
    void set_visual_recoil_recovery(float p_speed);
    float get_visual_recoil_recovery() const;

    /// Set the controller for repeated fire calls without argument.
    void set_controller(godot::XRController3D *p_controller);

protected:
    static void _bind_methods();

private:
    float haptic_intensity_ = 0.8f;
    float haptic_duration_ms_ = 50.0f;
    float visual_recoil_amount_ = 0.02f;
    float visual_recoil_recovery_ = 15.0f;
    float current_recoil_ = 0.0f;
    godot::XRController3D *controller_ = nullptr;
};

} // namespace rtv_vr

#endif // RTV_VR_RECOIL_FEEDBACK_H
