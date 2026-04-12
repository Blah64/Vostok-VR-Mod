#include "godot_api_bridge.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_action.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/xr_interface.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

void GodotApiBridge::inject_input_action(const StringName &p_action, bool p_pressed, float p_strength) {
    Ref<InputEventAction> event;
    event.instantiate();
    event->set_action(p_action);
    event->set_pressed(p_pressed);
    event->set_strength(p_strength);

    Input *input = Input::get_singleton();
    if (input) {
        input->parse_input_event(event);
    } else {
        UtilityFunctions::printerr("[RTV-VR] GodotApiBridge: Input singleton not available.");
    }
}

XRServer *GodotApiBridge::get_xr_server() {
    return XRServer::get_singleton();
}

Viewport *GodotApiBridge::get_viewport() {
    SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
    if (tree) {
        return tree->get_root();
    }
    return nullptr;
}

void GodotApiBridge::add_to_scene(Node *p_parent, Node *p_child) {
    if (!p_parent || !p_child) {
        UtilityFunctions::printerr("[RTV-VR] GodotApiBridge::add_to_scene: null parent or child.");
        return;
    }
    p_parent->call_deferred("add_child", p_child);
}

void GodotApiBridge::remove_from_scene(Node *p_node) {
    if (!p_node) {
        UtilityFunctions::printerr("[RTV-VR] GodotApiBridge::remove_from_scene: null node.");
        return;
    }
    p_node->call_deferred("queue_free");
}

bool GodotApiBridge::is_xr_available() {
    XRServer *server = XRServer::get_singleton();
    if (!server) {
        return false;
    }
    Ref<XRInterface> iface = server->find_interface("OpenXR");
    return iface.is_valid();
}

} // namespace rtv_vr
