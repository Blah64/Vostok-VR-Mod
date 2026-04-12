#include "action_mapper.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_action.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

ActionMapper::ActionMapper() = default;
ActionMapper::~ActionMapper() = default;

bool ActionMapper::load_bindings(const String &p_path) {
    if (!FileAccess::file_exists(p_path)) {
        ERR_PRINT(String("ActionMapper: Binding file not found: ") + p_path);
        return false;
    }

    Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ);
    ERR_FAIL_COND_V_MSG(file.is_null(), false,
            String("ActionMapper: Could not open binding file: ") + p_path);

    String json_text = file->get_as_text();
    file->close();

    Ref<JSON> json;
    json.instantiate();
    Error err = json->parse(json_text);
    if (err != OK) {
        ERR_PRINT(String("ActionMapper: JSON parse error at line ") +
                String::num_int64(json->get_error_line()) + ": " +
                json->get_error_message());
        return false;
    }

    Variant data = json->get_data();
    ERR_FAIL_COND_V_MSG(data.get_type() != Variant::DICTIONARY, false,
            "ActionMapper: Root element must be a Dictionary.");

    Dictionary root = data;
    ERR_FAIL_COND_V_MSG(!root.has("bindings"), false,
            "ActionMapper: Missing 'bindings' key in action map.");

    Array bindings_array = root["bindings"];

    clear_bindings();

    for (int i = 0; i < bindings_array.size(); i++) {
        Dictionary entry = bindings_array[i];
        ERR_CONTINUE_MSG(!entry.has("openxr_action"),
                String("ActionMapper: Binding entry ") + String::num_int64(i) +
                " missing 'openxr_action'.");

        ActionBinding binding;
        binding.openxr_action = entry["openxr_action"];
        binding.godot_action = entry.get("godot_action", "");
        binding.threshold = entry.get("threshold", 0.5f);
        binding.is_analog = entry.get("is_analog", false);
        binding.is_vector2 = entry.get("is_vector2", false);
        binding.godot_action_x = entry.get("godot_action_x", "");
        binding.godot_action_y = entry.get("godot_action_y", "");

        bindings_[binding.openxr_action] = binding;
    }

    if (root.has("deadzone")) {
        deadzone_ = root["deadzone"];
    }

    UtilityFunctions::print("ActionMapper: Loaded ", bindings_.size(), " bindings from ", p_path);
    return true;
}

void ActionMapper::on_button_pressed(const String &p_action_name) {
    if (!bindings_.has(p_action_name)) {
        return;
    }

    const ActionBinding &binding = bindings_[p_action_name];
    if (binding.godot_action.is_empty()) {
        return;
    }

    inject_action(StringName(binding.godot_action), true, 1.0f);
}

void ActionMapper::on_button_released(const String &p_action_name) {
    if (!bindings_.has(p_action_name)) {
        return;
    }

    const ActionBinding &binding = bindings_[p_action_name];
    if (binding.godot_action.is_empty()) {
        return;
    }

    inject_action(StringName(binding.godot_action), false, 0.0f);
}

void ActionMapper::on_float_changed(const String &p_action_name, float p_value) {
    if (!bindings_.has(p_action_name)) {
        return;
    }

    const ActionBinding &binding = bindings_[p_action_name];
    if (binding.godot_action.is_empty()) {
        return;
    }

    bool was_pressed = analog_pressed_state_.has(p_action_name) &&
            analog_pressed_state_[p_action_name];
    bool is_pressed = p_value >= binding.threshold;

    if (is_pressed && !was_pressed) {
        inject_action(StringName(binding.godot_action), true, p_value);
        analog_pressed_state_[p_action_name] = true;
    } else if (!is_pressed && was_pressed) {
        inject_action(StringName(binding.godot_action), false, 0.0f);
        analog_pressed_state_[p_action_name] = false;
    } else if (is_pressed && was_pressed && binding.is_analog) {
        // Continuously update strength for analog inputs while held.
        inject_action(StringName(binding.godot_action), true, p_value);
    }
}

void ActionMapper::on_vector2_changed(const String &p_action_name, Vector2 p_value) {
    if (!bindings_.has(p_action_name)) {
        return;
    }

    const ActionBinding &binding = bindings_[p_action_name];
    if (!binding.is_vector2) {
        return;
    }

    // Apply deadzone.
    float length = p_value.length();
    Vector2 adjusted = p_value;
    if (length < deadzone_) {
        adjusted = Vector2(0.0f, 0.0f);
    } else {
        // Rescale so that the range [deadzone, 1.0] maps to [0.0, 1.0].
        float scale = (length - deadzone_) / (1.0f - deadzone_);
        adjusted = p_value.normalized() * scale;
        adjusted.x = CLAMP(adjusted.x, -1.0f, 1.0f);
        adjusted.y = CLAMP(adjusted.y, -1.0f, 1.0f);
    }

    // Map X axis.
    if (!binding.godot_action_x.is_empty()) {
        float abs_x = Math::abs(adjusted.x);
        bool pressed_x = abs_x > 0.0f;
        inject_action(StringName(binding.godot_action_x), pressed_x, abs_x);
    }

    // Map Y axis.
    if (!binding.godot_action_y.is_empty()) {
        float abs_y = Math::abs(adjusted.y);
        bool pressed_y = abs_y > 0.0f;
        inject_action(StringName(binding.godot_action_y), pressed_y, abs_y);
    }

    // Also map to the primary action if provided (for combined stick input).
    if (!binding.godot_action.is_empty()) {
        bool pressed = length >= deadzone_;
        inject_action(StringName(binding.godot_action), pressed, length);
    }
}

void ActionMapper::set_deadzone(float p_deadzone) {
    deadzone_ = CLAMP(p_deadzone, 0.0f, 1.0f);
}

float ActionMapper::get_deadzone() const {
    return deadzone_;
}

int ActionMapper::get_binding_count() const {
    return static_cast<int>(bindings_.size());
}

void ActionMapper::clear_bindings() {
    bindings_.clear();
    analog_pressed_state_.clear();
}

void ActionMapper::inject_action(const StringName &p_action, bool p_pressed, float p_strength) {
    Ref<InputEventAction> event;
    event.instantiate();
    event->set_action(p_action);
    event->set_pressed(p_pressed);
    event->set_strength(p_strength);

    Input *input = Input::get_singleton();
    ERR_FAIL_NULL(input);
    input->parse_input_event(event);
}

void ActionMapper::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_bindings", "path"), &ActionMapper::load_bindings);
    ClassDB::bind_method(D_METHOD("on_button_pressed", "action_name"), &ActionMapper::on_button_pressed);
    ClassDB::bind_method(D_METHOD("on_button_released", "action_name"), &ActionMapper::on_button_released);
    ClassDB::bind_method(D_METHOD("on_float_changed", "action_name", "value"), &ActionMapper::on_float_changed);
    ClassDB::bind_method(D_METHOD("on_vector2_changed", "action_name", "value"), &ActionMapper::on_vector2_changed);
    ClassDB::bind_method(D_METHOD("set_deadzone", "deadzone"), &ActionMapper::set_deadzone);
    ClassDB::bind_method(D_METHOD("get_deadzone"), &ActionMapper::get_deadzone);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "deadzone", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"),
            "set_deadzone", "get_deadzone");
    ClassDB::bind_method(D_METHOD("get_binding_count"), &ActionMapper::get_binding_count);
    ClassDB::bind_method(D_METHOD("clear_bindings"), &ActionMapper::clear_bindings);
}

} // namespace rtv_vr
