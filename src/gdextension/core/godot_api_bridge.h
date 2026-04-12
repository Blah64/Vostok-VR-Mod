#ifndef RTV_VR_GODOT_API_BRIDGE_H
#define RTV_VR_GODOT_API_BRIDGE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/xr_server.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace rtv_vr {

/// Static utility class providing convenience wrappers around Godot APIs.
/// Not registered as a Godot class -- all methods are static.
class GodotApiBridge {
public:
    GodotApiBridge() = delete;

    /// Creates and dispatches an InputEventAction through the Input singleton.
    static void inject_input_action(const godot::StringName &p_action, bool p_pressed, float p_strength = 1.0f);

    /// Returns the XRServer singleton.
    static godot::XRServer *get_xr_server();

    /// Returns the main viewport of the scene tree.
    static godot::Viewport *get_viewport();

    /// Adds a child node using call_deferred to be thread-safe.
    static void add_to_scene(godot::Node *p_parent, godot::Node *p_child);

    /// Removes a node from the tree using call_deferred queue_free.
    static void remove_from_scene(godot::Node *p_node);

    /// Checks whether an OpenXR interface is available.
    static bool is_xr_available();
};

} // namespace rtv_vr

#endif // RTV_VR_GODOT_API_BRIDGE_H
