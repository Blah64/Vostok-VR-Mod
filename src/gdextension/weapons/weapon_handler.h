#ifndef RTV_VR_WEAPON_HANDLER_H
#define RTV_VR_WEAPON_HANDLER_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace rtv_vr {

class WeaponHandler : public godot::Node3D {
    GDCLASS(WeaponHandler, godot::Node3D)

public:
    WeaponHandler();
    ~WeaponHandler() override = default;

    void _process(double p_delta) override;

    /// Attach a weapon to the given controller.
    void attach_weapon(godot::Node3D *p_weapon, godot::XRController3D *p_controller);

    /// Detach the weapon and restore its original parent/transform.
    void detach_weapon();

    /// Set position offset from controller to weapon grip.
    void set_grip_offset(const godot::Vector3 &p_offset);

    /// Set rotation offset in euler degrees.
    void set_grip_rotation(const godot::Vector3 &p_euler_degrees);

    /// Enable two-handed aiming mode.
    void enable_two_hand_mode(godot::XRController3D *p_off_hand);

    /// Disable two-handed aiming mode.
    void disable_two_hand_mode();

    /// Returns true if a weapon is currently attached.
    bool is_attached() const;

    /// Returns the currently attached weapon node.
    godot::Node3D *get_weapon() const;

protected:
    static void _bind_methods();

private:
    godot::Node3D *weapon_node_ = nullptr;
    godot::XRController3D *primary_hand_ = nullptr;
    godot::XRController3D *off_hand_ = nullptr;
    godot::Transform3D grip_offset_;
    godot::Transform3D original_weapon_transform_;
    godot::Node *original_weapon_parent_ = nullptr;
    bool attached_ = false;
    bool two_hand_mode_ = false;
};

} // namespace rtv_vr

#endif // RTV_VR_WEAPON_HANDLER_H
