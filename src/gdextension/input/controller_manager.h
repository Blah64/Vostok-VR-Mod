#ifndef RTV_VR_CONTROLLER_MANAGER_H
#define RTV_VR_CONTROLLER_MANAGER_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/classes/xr_origin3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace rtv_vr {

class ActionMapper;

class ControllerManager : public godot::Node {
    GDCLASS(ControllerManager, godot::Node)

public:
    ControllerManager();
    ~ControllerManager() override;

    bool install(godot::XROrigin3D *p_origin);
    void uninstall();

    godot::XRController3D *get_left() const;
    godot::XRController3D *get_right() const;

    void set_action_mapper(const godot::Ref<ActionMapper> &p_mapper);
    godot::Ref<ActionMapper> get_action_mapper() const;

    // Godot lifecycle
    void _process(double p_delta) override;

    // Signal handlers
    void _on_button_pressed(const godot::String &p_name);
    void _on_button_released(const godot::String &p_name);
    void _on_float_changed(const godot::String &p_name, float p_value);
    void _on_vector2_changed(const godot::String &p_name, godot::Vector2 p_value);

protected:
    static void _bind_methods();

private:
    void connect_controller_signals(godot::XRController3D *p_controller);
    void disconnect_controller_signals(godot::XRController3D *p_controller);

    godot::XRController3D *left_controller_ = nullptr;
    godot::XRController3D *right_controller_ = nullptr;
    godot::XROrigin3D *xr_origin_ = nullptr;
    godot::Ref<ActionMapper> action_mapper_;

    bool left_tracking_active_ = false;
    bool right_tracking_active_ = false;
    bool installed_ = false;
};

} // namespace rtv_vr

#endif // RTV_VR_CONTROLLER_MANAGER_H
