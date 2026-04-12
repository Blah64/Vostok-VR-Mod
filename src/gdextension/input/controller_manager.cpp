#include "controller_manager.h"
#include "action_mapper.h"

#include <godot_cpp/classes/xr_positional_tracker.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

ControllerManager::ControllerManager() = default;

ControllerManager::~ControllerManager() {
    if (installed_) {
        uninstall();
    }
}

bool ControllerManager::install(XROrigin3D *p_origin) {
    ERR_FAIL_NULL_V(p_origin, false);

    if (installed_) {
        UtilityFunctions::push_warning("ControllerManager: Already installed, uninstalling first.");
        uninstall();
    }

    xr_origin_ = p_origin;

    // Create left controller.
    left_controller_ = memnew(XRController3D);
    left_controller_->set_name("VRLeftController");
    left_controller_->set_tracker(StringName("left_hand"));
    xr_origin_->add_child(left_controller_);

    // Create right controller.
    right_controller_ = memnew(XRController3D);
    right_controller_->set_name("VRRightController");
    right_controller_->set_tracker(StringName("right_hand"));
    xr_origin_->add_child(right_controller_);

    // Connect input signals on both controllers.
    connect_controller_signals(left_controller_);
    connect_controller_signals(right_controller_);

    installed_ = true;
    UtilityFunctions::print("ControllerManager: Installed left and right XRController3D nodes.");
    return true;
}

void ControllerManager::uninstall() {
    if (!installed_) {
        return;
    }

    if (left_controller_ != nullptr) {
        disconnect_controller_signals(left_controller_);
        if (left_controller_->get_parent() != nullptr) {
            left_controller_->get_parent()->remove_child(left_controller_);
        }
        memdelete(left_controller_);
        left_controller_ = nullptr;
    }

    if (right_controller_ != nullptr) {
        disconnect_controller_signals(right_controller_);
        if (right_controller_->get_parent() != nullptr) {
            right_controller_->get_parent()->remove_child(right_controller_);
        }
        memdelete(right_controller_);
        right_controller_ = nullptr;
    }

    xr_origin_ = nullptr;
    left_tracking_active_ = false;
    right_tracking_active_ = false;
    installed_ = false;

    UtilityFunctions::print("ControllerManager: Uninstalled.");
}

XRController3D *ControllerManager::get_left() const {
    return left_controller_;
}

XRController3D *ControllerManager::get_right() const {
    return right_controller_;
}

void ControllerManager::set_action_mapper(const Ref<ActionMapper> &p_mapper) {
    action_mapper_ = p_mapper;
}

Ref<ActionMapper> ControllerManager::get_action_mapper() const {
    return action_mapper_;
}

void ControllerManager::_process(double p_delta) {
    if (!installed_) {
        return;
    }

    // Track whether controllers are actively tracking.
    if (left_controller_ != nullptr) {
        bool active = left_controller_->get_has_tracking_data();
        if (active != left_tracking_active_) {
            left_tracking_active_ = active;
            if (active) {
                UtilityFunctions::print("ControllerManager: Left controller tracking active.");
            } else {
                UtilityFunctions::print("ControllerManager: Left controller tracking lost.");
            }
        }
    }

    if (right_controller_ != nullptr) {
        bool active = right_controller_->get_has_tracking_data();
        if (active != right_tracking_active_) {
            right_tracking_active_ = active;
            if (active) {
                UtilityFunctions::print("ControllerManager: Right controller tracking active.");
            } else {
                UtilityFunctions::print("ControllerManager: Right controller tracking lost.");
            }
        }
    }
}

void ControllerManager::_on_button_pressed(const String &p_name) {
    if (action_mapper_.is_valid()) {
        action_mapper_->on_button_pressed(p_name);
    }
}

void ControllerManager::_on_button_released(const String &p_name) {
    if (action_mapper_.is_valid()) {
        action_mapper_->on_button_released(p_name);
    }
}

void ControllerManager::_on_float_changed(const String &p_name, float p_value) {
    if (action_mapper_.is_valid()) {
        action_mapper_->on_float_changed(p_name, p_value);
    }
}

void ControllerManager::_on_vector2_changed(const String &p_name, Vector2 p_value) {
    if (action_mapper_.is_valid()) {
        action_mapper_->on_vector2_changed(p_name, p_value);
    }
}

void ControllerManager::connect_controller_signals(XRController3D *p_controller) {
    ERR_FAIL_NULL(p_controller);

    p_controller->connect("button_pressed",
            Callable(this, "_on_button_pressed"));
    p_controller->connect("button_released",
            Callable(this, "_on_button_released"));
    p_controller->connect("input_float_changed",
            Callable(this, "_on_float_changed"));
    p_controller->connect("input_vector2_changed",
            Callable(this, "_on_vector2_changed"));
}

void ControllerManager::disconnect_controller_signals(XRController3D *p_controller) {
    ERR_FAIL_NULL(p_controller);

    if (p_controller->is_connected("button_pressed",
                Callable(this, "_on_button_pressed"))) {
        p_controller->disconnect("button_pressed",
                Callable(this, "_on_button_pressed"));
    }
    if (p_controller->is_connected("button_released",
                Callable(this, "_on_button_released"))) {
        p_controller->disconnect("button_released",
                Callable(this, "_on_button_released"));
    }
    if (p_controller->is_connected("input_float_changed",
                Callable(this, "_on_float_changed"))) {
        p_controller->disconnect("input_float_changed",
                Callable(this, "_on_float_changed"));
    }
    if (p_controller->is_connected("input_vector2_changed",
                Callable(this, "_on_vector2_changed"))) {
        p_controller->disconnect("input_vector2_changed",
                Callable(this, "_on_vector2_changed"));
    }
}

void ControllerManager::_bind_methods() {
    ClassDB::bind_method(D_METHOD("install", "origin"), &ControllerManager::install);
    ClassDB::bind_method(D_METHOD("uninstall"), &ControllerManager::uninstall);
    ClassDB::bind_method(D_METHOD("get_left"), &ControllerManager::get_left);
    ClassDB::bind_method(D_METHOD("get_right"), &ControllerManager::get_right);
    ClassDB::bind_method(D_METHOD("set_action_mapper", "mapper"), &ControllerManager::set_action_mapper);
    ClassDB::bind_method(D_METHOD("get_action_mapper"), &ControllerManager::get_action_mapper);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "action_mapper", PROPERTY_HINT_RESOURCE_TYPE, "ActionMapper"),
            "set_action_mapper", "get_action_mapper");

    // Signal handlers (must be bound so they can be used as Callables).
    ClassDB::bind_method(D_METHOD("_on_button_pressed", "name"), &ControllerManager::_on_button_pressed);
    ClassDB::bind_method(D_METHOD("_on_button_released", "name"), &ControllerManager::_on_button_released);
    ClassDB::bind_method(D_METHOD("_on_float_changed", "name", "value"), &ControllerManager::_on_float_changed);
    ClassDB::bind_method(D_METHOD("_on_vector2_changed", "name", "value"), &ControllerManager::_on_vector2_changed);

    // Signals emitted for external listeners.
    ADD_SIGNAL(MethodInfo("tracking_changed",
            PropertyInfo(Variant::STRING, "hand"),
            PropertyInfo(Variant::BOOL, "active")));
}

} // namespace rtv_vr
