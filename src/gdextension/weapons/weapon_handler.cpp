#include "weapon_handler.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

WeaponHandler::WeaponHandler() {
    set_process(true);
}

void WeaponHandler::_process(double p_delta) {
    if (!attached_ || weapon_node_ == nullptr || primary_hand_ == nullptr) {
        return;
    }

    Transform3D controller_xform = primary_hand_->get_global_transform();
    Transform3D target = controller_xform * grip_offset_;

    if (two_hand_mode_ && off_hand_ != nullptr) {
        // Two-hand aiming: orient weapon toward off-hand position.
        Vector3 primary_pos = controller_xform.origin;
        Vector3 secondary_pos = off_hand_->get_global_transform().origin;
        Vector3 forward = (secondary_pos - primary_pos).normalized();

        if (forward.length_squared() > 0.001f) {
            Vector3 up_hint = Vector3(0.0f, 1.0f, 0.0f);
            Vector3 right = up_hint.cross(forward).normalized();
            if (right.length_squared() < 0.001f) {
                right = Vector3(1.0f, 0.0f, 0.0f);
            }
            Vector3 up = forward.cross(right).normalized();

            Basis basis;
            basis.set_column(0, right);
            basis.set_column(1, up);
            basis.set_column(2, forward);

            target = Transform3D(basis, primary_pos) * grip_offset_;
        }
    }

    weapon_node_->set_global_transform(target);
}

void WeaponHandler::attach_weapon(Node3D *p_weapon, XRController3D *p_controller) {
    if (p_weapon == nullptr || p_controller == nullptr) {
        UtilityFunctions::push_warning("WeaponHandler::attach_weapon: null argument.");
        return;
    }

    // Detach previous weapon if any.
    if (attached_) {
        detach_weapon();
    }

    weapon_node_ = p_weapon;
    primary_hand_ = p_controller;

    // Store original state for restoration.
    original_weapon_parent_ = p_weapon->get_parent();
    original_weapon_transform_ = p_weapon->get_global_transform();

    // Reparent to the controller.
    if (original_weapon_parent_ != nullptr) {
        original_weapon_parent_->remove_child(p_weapon);
    }
    p_controller->add_child(p_weapon);
    p_weapon->set_transform(grip_offset_);

    attached_ = true;
}

void WeaponHandler::detach_weapon() {
    if (!attached_ || weapon_node_ == nullptr) {
        return;
    }

    // Remove from controller.
    Node *current_parent = weapon_node_->get_parent();
    if (current_parent != nullptr) {
        current_parent->remove_child(weapon_node_);
    }

    // Restore to original parent.
    if (original_weapon_parent_ != nullptr) {
        original_weapon_parent_->add_child(weapon_node_);
    }
    weapon_node_->set_global_transform(original_weapon_transform_);

    weapon_node_ = nullptr;
    primary_hand_ = nullptr;
    off_hand_ = nullptr;
    original_weapon_parent_ = nullptr;
    attached_ = false;
    two_hand_mode_ = false;
}

void WeaponHandler::set_grip_offset(const Vector3 &p_offset) {
    grip_offset_.origin = p_offset;
}

void WeaponHandler::set_grip_rotation(const Vector3 &p_euler_degrees) {
    Vector3 radians = Vector3(
        Math::deg_to_rad(p_euler_degrees.x),
        Math::deg_to_rad(p_euler_degrees.y),
        Math::deg_to_rad(p_euler_degrees.z));
    grip_offset_.basis = Basis::from_euler(radians);
}

void WeaponHandler::enable_two_hand_mode(XRController3D *p_off_hand) {
    if (p_off_hand == nullptr) {
        return;
    }
    off_hand_ = p_off_hand;
    two_hand_mode_ = true;
}

void WeaponHandler::disable_two_hand_mode() {
    off_hand_ = nullptr;
    two_hand_mode_ = false;
}

bool WeaponHandler::is_attached() const {
    return attached_;
}

Node3D *WeaponHandler::get_weapon() const {
    return weapon_node_;
}

void WeaponHandler::_bind_methods() {
    ClassDB::bind_method(D_METHOD("attach_weapon", "weapon", "controller"), &WeaponHandler::attach_weapon);
    ClassDB::bind_method(D_METHOD("detach_weapon"), &WeaponHandler::detach_weapon);
    ClassDB::bind_method(D_METHOD("set_grip_offset", "offset"), &WeaponHandler::set_grip_offset);
    ClassDB::bind_method(D_METHOD("set_grip_rotation", "euler_degrees"), &WeaponHandler::set_grip_rotation);
    ClassDB::bind_method(D_METHOD("enable_two_hand_mode", "off_hand"), &WeaponHandler::enable_two_hand_mode);
    ClassDB::bind_method(D_METHOD("disable_two_hand_mode"), &WeaponHandler::disable_two_hand_mode);
    ClassDB::bind_method(D_METHOD("is_attached"), &WeaponHandler::is_attached);
    ClassDB::bind_method(D_METHOD("get_weapon"), &WeaponHandler::get_weapon);

    ADD_GROUP("Grip", "grip_");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "grip_offset"), "set_grip_offset", "");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "grip_rotation"), "set_grip_rotation", "");
}

} // namespace rtv_vr
