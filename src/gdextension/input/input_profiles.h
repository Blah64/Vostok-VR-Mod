#ifndef RTV_VR_INPUT_PROFILES_H
#define RTV_VR_INPUT_PROFILES_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/templates/hash_map.hpp>

namespace rtv_vr {

class InputProfiles : public godot::RefCounted {
    GDCLASS(InputProfiles, godot::RefCounted)

public:
    InputProfiles();
    ~InputProfiles() override;

    bool load_profile(const godot::String &p_path);

    godot::String get_binding_path(const godot::String &p_action_name) const;
    godot::String get_profile_name() const;
    godot::String get_interaction_profile() const;

    static godot::String detect_active_profile();

protected:
    static void _bind_methods();

private:
    godot::String profile_name_;
    godot::String interaction_profile_;
    godot::HashMap<godot::String, godot::String> binding_paths_;
    bool loaded_ = false;
};

} // namespace rtv_vr

#endif // RTV_VR_INPUT_PROFILES_H
