#include "xr_settings.h"

#include <godot_cpp/classes/xr_server.hpp>
#include <godot_cpp/classes/xr_interface.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

void XRSettings::_bind_methods() {
    ClassDB::bind_method(D_METHOD("apply_from_config", "config"), &XRSettings::apply_from_config);
    ClassDB::bind_method(D_METHOD("set_render_scale", "scale"), &XRSettings::set_render_scale);
    ClassDB::bind_method(D_METHOD("set_refresh_rate", "rate"), &XRSettings::set_refresh_rate);
    ClassDB::bind_method(D_METHOD("set_foveation", "level"), &XRSettings::set_foveation);
    ClassDB::bind_method(D_METHOD("set_world_scale", "scale"), &XRSettings::set_world_scale);
    ClassDB::bind_method(D_METHOD("get_recommended_render_scale"), &XRSettings::get_recommended_render_scale);
}

void XRSettings::apply_from_config(const Dictionary &p_config) {
    UtilityFunctions::print("[RTV-VR] XRSettings: Applying settings from config...");

    if (p_config.has("render_scale")) {
        set_render_scale((float)(double)p_config["render_scale"]);
    }
    if (p_config.has("refresh_rate")) {
        set_refresh_rate((int)(int64_t)p_config["refresh_rate"]);
    }
    if (p_config.has("foveation")) {
        set_foveation((int)(int64_t)p_config["foveation"]);
    }
    if (p_config.has("world_scale")) {
        set_world_scale((float)(double)p_config["world_scale"]);
    }

    UtilityFunctions::print("[RTV-VR] XRSettings: Settings applied.");
}

void XRSettings::set_render_scale(float p_scale) {
    p_scale = CLAMP(p_scale, 0.25f, 2.0f);

    SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
    if (tree) {
        Viewport *root_vp = tree->get_root();
        if (root_vp) {
            root_vp->set_scaling_3d_scale(p_scale);
            UtilityFunctions::print("[RTV-VR] XRSettings: Render scale = ", p_scale);
        }
    }
}

void XRSettings::set_refresh_rate(int p_rate) {
    XRServer *server = XRServer::get_singleton();
    if (!server) {
        UtilityFunctions::printerr("[RTV-VR] XRSettings: XRServer not available for refresh rate.");
        return;
    }

    Ref<XRInterface> iface = server->get_primary_interface();
    if (iface.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] XRSettings: No primary XR interface for refresh rate.");
        return;
    }

    // Set display refresh rate through the interface property
    iface->set("display_refresh_rate", (double)p_rate);
    UtilityFunctions::print("[RTV-VR] XRSettings: Requested refresh rate = ", p_rate, " Hz");
}

void XRSettings::set_foveation(int p_level) {
    p_level = CLAMP(p_level, 0, 3);

    XRServer *server = XRServer::get_singleton();
    if (!server) {
        UtilityFunctions::printerr("[RTV-VR] XRSettings: XRServer not available for foveation.");
        return;
    }

    Ref<XRInterface> iface = server->get_primary_interface();
    if (iface.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] XRSettings: No primary XR interface for foveation.");
        return;
    }

    iface->set("foveation_level", p_level);
    iface->set("foveation_dynamic", p_level > 0);
    UtilityFunctions::print("[RTV-VR] XRSettings: Foveation level = ", p_level,
                             (p_level > 0 ? " (dynamic enabled)" : " (off)"));
}

void XRSettings::set_world_scale(float p_scale) {
    p_scale = CLAMP(p_scale, 0.1f, 10.0f);

    XRServer *server = XRServer::get_singleton();
    if (!server) {
        UtilityFunctions::printerr("[RTV-VR] XRSettings: XRServer not available for world scale.");
        return;
    }

    server->set_world_scale(p_scale);
    UtilityFunctions::print("[RTV-VR] XRSettings: World scale = ", p_scale);
}

float XRSettings::get_recommended_render_scale() const {
    XRServer *server = XRServer::get_singleton();
    if (!server) {
        return 1.0f;
    }

    Ref<XRInterface> iface = server->get_primary_interface();
    if (iface.is_null()) {
        return 1.0f;
    }

    // Query the render target size to infer a recommendation.
    // The XR runtime's native resolution hints at the ideal scale.
    // If the interface exposes render_target_size_multiplier, read it back;
    // otherwise return a sensible default.
    Variant multiplier = iface->get("render_target_size_multiplier");
    if (multiplier.get_type() == Variant::FLOAT) {
        return (float)(double)multiplier;
    }

    // Fallback: return 1.0 as the baseline recommendation
    return 1.0f;
}

} // namespace rtv_vr
