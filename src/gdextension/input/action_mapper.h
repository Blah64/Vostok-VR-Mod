#ifndef RTV_VR_ACTION_MAPPER_H
#define RTV_VR_ACTION_MAPPER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/templates/hash_map.hpp>

namespace rtv_vr {

class ActionMapper : public godot::RefCounted {
    GDCLASS(ActionMapper, godot::RefCounted)

public:
    struct ActionBinding {
        godot::String openxr_action;
        godot::String godot_action;
        float threshold = 0.5f;
        bool is_analog = false;
        bool is_vector2 = false;
        godot::String godot_action_x;
        godot::String godot_action_y;
    };

    ActionMapper();
    ~ActionMapper() override;

    bool load_bindings(const godot::String &p_path);

    void on_button_pressed(const godot::String &p_action_name);
    void on_button_released(const godot::String &p_action_name);
    void on_float_changed(const godot::String &p_action_name, float p_value);
    void on_vector2_changed(const godot::String &p_action_name, godot::Vector2 p_value);

    void set_deadzone(float p_deadzone);
    float get_deadzone() const;

    int get_binding_count() const;
    void clear_bindings();

protected:
    static void _bind_methods();

private:
    void inject_action(const godot::StringName &p_action, bool p_pressed, float p_strength = 1.0f);

    godot::HashMap<godot::String, ActionBinding> bindings_;
    godot::HashMap<godot::String, bool> analog_pressed_state_;
    float deadzone_ = 0.15f;
};

} // namespace rtv_vr

#endif // RTV_VR_ACTION_MAPPER_H
