#include "scene_inspector.h"

#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

void SceneInspector::_bind_methods() {
    ClassDB::bind_method(D_METHOD("find_camera", "root"), &SceneInspector::find_camera);
    ClassDB::bind_method(D_METHOD("find_player_body", "root"), &SceneInspector::find_player_body);
    ClassDB::bind_method(D_METHOD("find_weapon_nodes", "root"), &SceneInspector::find_weapon_nodes);
    ClassDB::bind_method(D_METHOD("find_ui_controls", "root"), &SceneInspector::find_ui_controls);
    ClassDB::bind_method(D_METHOD("find_node_by_class", "root", "class_name"), &SceneInspector::find_node_by_class);
    ClassDB::bind_method(D_METHOD("find_nodes_by_class", "root", "class_name"), &SceneInspector::find_nodes_by_class);
}

Camera3D *SceneInspector::find_camera(Node *p_root) {
    if (!p_root) {
        return nullptr;
    }
    Node *result = find_node_by_class(p_root, "Camera3D");
    return Object::cast_to<Camera3D>(result);
}

CharacterBody3D *SceneInspector::find_player_body(Node *p_root) {
    if (!p_root) {
        return nullptr;
    }
    Node *result = find_node_by_class(p_root, "CharacterBody3D");
    return Object::cast_to<CharacterBody3D>(result);
}

TypedArray<Node3D> SceneInspector::find_weapon_nodes(Node *p_root) {
    TypedArray<Node3D> weapons;
    if (!p_root) {
        return weapons;
    }

    // First, search by common weapon-related class names
    TypedArray<Node> node3d_nodes;
    recursive_search(p_root, "Node3D", node3d_nodes);

    for (int i = 0; i < node3d_nodes.size(); i++) {
        Node *node = Object::cast_to<Node>(node3d_nodes[i]);
        if (node && is_weapon_name(node->get_name())) {
            Node3D *n3d = Object::cast_to<Node3D>(node);
            if (n3d) {
                weapons.append(n3d);
            }
        }
    }

    return weapons;
}

TypedArray<Control> SceneInspector::find_ui_controls(Node *p_root) {
    TypedArray<Control> controls;
    if (!p_root) {
        return controls;
    }

    // Find all CanvasLayer nodes first, then collect Controls within them
    TypedArray<Node> canvas_layers;
    recursive_search(p_root, "CanvasLayer", canvas_layers);

    for (int i = 0; i < canvas_layers.size(); i++) {
        Node *layer = Object::cast_to<Node>(canvas_layers[i]);
        if (!layer) {
            continue;
        }
        TypedArray<Node> layer_controls;
        recursive_search(layer, "Control", layer_controls);
        for (int j = 0; j < layer_controls.size(); j++) {
            Control *ctrl = Object::cast_to<Control>(layer_controls[j]);
            if (ctrl) {
                controls.append(ctrl);
            }
        }
    }

    return controls;
}

Node *SceneInspector::find_node_by_class(Node *p_root, const StringName &p_class_name) {
    if (!p_root) {
        return nullptr;
    }

    if (p_root->is_class(p_class_name)) {
        return p_root;
    }

    int child_count = p_root->get_child_count();
    for (int i = 0; i < child_count; i++) {
        Node *child = p_root->get_child(i);
        Node *found = find_node_by_class(child, p_class_name);
        if (found) {
            return found;
        }
    }

    return nullptr;
}

TypedArray<Node> SceneInspector::find_nodes_by_class(Node *p_root, const StringName &p_class_name) {
    TypedArray<Node> results;
    if (p_root) {
        recursive_search(p_root, p_class_name, results);
    }
    return results;
}

void SceneInspector::recursive_search(Node *p_node, const StringName &p_class_name,
                                       TypedArray<Node> &r_results) {
    if (!p_node) {
        return;
    }

    if (p_node->is_class(p_class_name)) {
        r_results.append(p_node);
    }

    int child_count = p_node->get_child_count();
    for (int i = 0; i < child_count; i++) {
        recursive_search(p_node->get_child(i), p_class_name, r_results);
    }
}

bool SceneInspector::is_weapon_name(const String &p_name) const {
    String lower = p_name.to_lower();
    // Match common weapon-related name patterns
    static const char *patterns[] = {
        "weapon", "gun", "rifle", "pistol", "shotgun", "smg",
        "firearm", "barrel", "muzzle", "magazine", "ak", "m4",
        "sks", "mosin", "makarov", "mp5", "stock", "grip",
        nullptr
    };

    for (int i = 0; patterns[i] != nullptr; i++) {
        if (lower.find(patterns[i]) != -1) {
            return true;
        }
    }
    return false;
}

} // namespace rtv_vr
