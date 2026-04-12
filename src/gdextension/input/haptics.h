#ifndef RTV_VR_HAPTICS_H
#define RTV_VR_HAPTICS_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace rtv_vr {

class Haptics : public godot::RefCounted {
    GDCLASS(Haptics, godot::RefCounted)

public:
    Haptics();
    ~Haptics() override;

    void trigger_haptic(godot::XRController3D *p_controller, float p_intensity, float p_duration_sec);

    void pulse_left(float p_intensity, float p_duration);
    void pulse_right(float p_intensity, float p_duration);

    void set_controllers(godot::XRController3D *p_left, godot::XRController3D *p_right);
    void stop_all();

protected:
    static void _bind_methods();

private:
    godot::XRController3D *left_controller_ = nullptr;
    godot::XRController3D *right_controller_ = nullptr;
};

} // namespace rtv_vr

#endif // RTV_VR_HAPTICS_H
