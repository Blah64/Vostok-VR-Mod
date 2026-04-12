#ifndef RTV_VR_SCENE_INSPECTOR_H
#define RTV_VR_SCENE_INSPECTOR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace rtv_vr {

class SceneInspector : public godot::RefCounted {
    GDCLASS(SceneInspector, godot::RefCounted)

public:
    SceneInspector() = default;
    ~SceneInspector() override = default;

    // Primary search methods
    godot::Camera3D *find_camera(godot::Node *p_root);
    godot::CharacterBody3D *find_player_body(godot::Node *p_root);
    godot::TypedArray<godot::Node3D> find_weapon_nodes(godot::Node *p_root);
    godot::TypedArray<godot::Control> find_ui_controls(godot::Node *p_root);

    // Generic search helpers
    godot::Node *find_node_by_class(godot::Node *p_root, const godot::StringName &p_class_name);
    godot::TypedArray<godot::Node> find_nodes_by_class(godot::Node *p_root, const godot::StringName &p_class_name);

protected:
    static void _bind_methods();

private:
    void recursive_search(godot::Node *p_node, const godot::StringName &p_class_name,
                          godot::TypedArray<godot::Node> &r_results);
    bool is_weapon_name(const godot::String &p_name) const;
};

} // namespace rtv_vr

#endif // RTV_VR_SCENE_INSPECTOR_H
