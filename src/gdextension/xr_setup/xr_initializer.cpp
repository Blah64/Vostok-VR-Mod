#include "xr_initializer.h"

#include <godot_cpp/classes/xr_server.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

void XRInitializer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("activate_openxr"), &XRInitializer::activate_openxr);
    ClassDB::bind_method(D_METHOD("apply_settings", "config"), &XRInitializer::apply_settings);
    ClassDB::bind_method(D_METHOD("is_xr_active"), &XRInitializer::is_xr_active);

    // Internal signal handlers (bound so they can be connected via Callable)
    ClassDB::bind_method(D_METHOD("_on_session_begun"), &XRInitializer::_on_session_begun);
    ClassDB::bind_method(D_METHOD("_on_session_stopping"), &XRInitializer::_on_session_stopping);
    ClassDB::bind_method(D_METHOD("_on_session_focussed"), &XRInitializer::_on_session_focussed);

    // Enum constants
    BIND_ENUM_CONSTANT(RESULT_SUCCESS);
    BIND_ENUM_CONSTANT(RESULT_NO_INTERFACE);
    BIND_ENUM_CONSTANT(RESULT_INIT_FAILED);
    BIND_ENUM_CONSTANT(RESULT_ALREADY_ACTIVE);

    // Signals
    ADD_SIGNAL(MethodInfo("xr_session_begun"));
    ADD_SIGNAL(MethodInfo("xr_session_stopping"));
    ADD_SIGNAL(MethodInfo("xr_session_focussed"));
}

XRInitializer::Result XRInitializer::activate_openxr() {
    UtilityFunctions::print("[RTV-VR] XRInitializer: Attempting to activate OpenXR...");

    // Step 1: Get XRServer singleton
    XRServer *server = XRServer::get_singleton();
    if (!server) {
        UtilityFunctions::printerr("[RTV-VR] XRInitializer: XRServer singleton not found.");
        return RESULT_NO_INTERFACE;
    }

    // Step 2: Find the OpenXR interface
    Ref<XRInterface> iface = server->find_interface("OpenXR");
    if (iface.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] XRInitializer: OpenXR interface not found. "
                                    "Ensure the OpenXR plugin is enabled.");
        return RESULT_NO_INTERFACE;
    }

    // Check if already initialized
    if (iface->is_initialized()) {
        UtilityFunctions::print("[RTV-VR] XRInitializer: OpenXR interface already active.");
        m_xr_interface = iface;
        return RESULT_ALREADY_ACTIVE;
    }

    // Step 3: Initialize the interface
    if (!iface->initialize()) {
        UtilityFunctions::printerr("[RTV-VR] XRInitializer: Failed to initialize OpenXR interface.");
        return RESULT_INIT_FAILED;
    }

    m_xr_interface = iface;

    // Step 4: Set as primary interface
    server->set_primary_interface(iface);

    // Configure the main viewport for XR
    SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
    if (tree) {
        Viewport *root_vp = tree->get_root();
        if (root_vp) {
            root_vp->set_use_xr(true);
            UtilityFunctions::print("[RTV-VR] XRInitializer: Root viewport set to use XR.");
        }
    }

    // Step 5: Connect to session signals
    if (iface->has_signal("session_begun")) {
        iface->connect("session_begun", Callable(this, "_on_session_begun"));
    }
    if (iface->has_signal("session_stopping")) {
        iface->connect("session_stopping", Callable(this, "_on_session_stopping"));
    }
    if (iface->has_signal("session_focussed")) {
        iface->connect("session_focussed", Callable(this, "_on_session_focussed"));
    }

    UtilityFunctions::print("[RTV-VR] XRInitializer: OpenXR activated successfully.");
    return RESULT_SUCCESS;
}

void XRInitializer::apply_settings(const Dictionary &p_config) {
    if (m_xr_interface.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] XRInitializer::apply_settings: No active XR interface.");
        return;
    }

    if (p_config.has("render_scale")) {
        float scale = p_config["render_scale"];
        m_xr_interface->set("render_target_size_multiplier", scale);
        UtilityFunctions::print("[RTV-VR] XRInitializer: Render scale set to ", scale);
    }

    if (p_config.has("refresh_rate")) {
        int rate = p_config["refresh_rate"];
        // OpenXR display refresh rate is set through the interface
        m_xr_interface->set("display_refresh_rate", (double)rate);
        UtilityFunctions::print("[RTV-VR] XRInitializer: Refresh rate requested: ", rate, " Hz");
    }

    if (p_config.has("foveation")) {
        int level = p_config["foveation"];
        m_xr_interface->set("foveation_level", level);
        m_xr_interface->set("foveation_dynamic", level > 0);
        UtilityFunctions::print("[RTV-VR] XRInitializer: Foveation level set to ", level);
    }
}

bool XRInitializer::is_xr_active() const {
    if (m_xr_interface.is_null()) {
        return false;
    }
    return m_xr_interface->is_initialized();
}

void XRInitializer::_on_session_begun() {
    UtilityFunctions::print("[RTV-VR] XR session begun.");
    emit_signal("xr_session_begun");
}

void XRInitializer::_on_session_stopping() {
    UtilityFunctions::print("[RTV-VR] XR session stopping.");
    emit_signal("xr_session_stopping");
}

void XRInitializer::_on_session_focussed() {
    UtilityFunctions::print("[RTV-VR] XR session focussed.");
    emit_signal("xr_session_focussed");
}

} // namespace rtv_vr
