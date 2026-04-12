#include "input_profiles.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/xr_interface.hpp>
#include <godot_cpp/classes/xr_server.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

InputProfiles::InputProfiles() = default;
InputProfiles::~InputProfiles() = default;

bool InputProfiles::load_profile(const String &p_path) {
    if (!FileAccess::file_exists(p_path)) {
        ERR_PRINT(String("InputProfiles: Profile file not found: ") + p_path);
        return false;
    }

    Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ);
    ERR_FAIL_COND_V_MSG(file.is_null(), false,
            String("InputProfiles: Could not open profile file: ") + p_path);

    String json_text = file->get_as_text();
    file->close();

    Ref<JSON> json;
    json.instantiate();
    Error err = json->parse(json_text);
    if (err != OK) {
        ERR_PRINT(String("InputProfiles: JSON parse error at line ") +
                String::num_int64(json->get_error_line()) + ": " +
                json->get_error_message());
        return false;
    }

    Variant data = json->get_data();
    ERR_FAIL_COND_V_MSG(data.get_type() != Variant::DICTIONARY, false,
            "InputProfiles: Root element must be a Dictionary.");

    Dictionary root = data;

    profile_name_ = root.get("profile_name", "");
    interaction_profile_ = root.get("interaction_profile", "");

    binding_paths_.clear();

    if (root.has("bindings")) {
        Dictionary bindings = root["bindings"];
        Array keys = bindings.keys();
        for (int i = 0; i < keys.size(); i++) {
            String key = keys[i];
            String value = bindings[key];
            binding_paths_[key] = value;
        }
    }

    loaded_ = true;
    UtilityFunctions::print("InputProfiles: Loaded profile '", profile_name_,
            "' with ", binding_paths_.size(), " bindings.");
    return true;
}

String InputProfiles::get_binding_path(const String &p_action_name) const {
    if (!binding_paths_.has(p_action_name)) {
        return String();
    }
    return binding_paths_[p_action_name];
}

String InputProfiles::get_profile_name() const {
    return profile_name_;
}

String InputProfiles::get_interaction_profile() const {
    return interaction_profile_;
}

String InputProfiles::detect_active_profile() {
    XRServer *xr_server = XRServer::get_singleton();
    ERR_FAIL_NULL_V_MSG(xr_server, String(),
            "InputProfiles: XRServer singleton not available.");

    Ref<XRInterface> xr_interface = xr_server->get_primary_interface();
    if (xr_interface.is_null()) {
        UtilityFunctions::push_warning("InputProfiles: No primary XR interface found.");
        return String();
    }

    String interface_name = xr_interface->get_name();

    // Attempt to determine controller type from the interface name and system info.
    // Common profiles based on OpenXR interaction profiles.
    if (interface_name.contains("oculus") || interface_name.contains("meta")) {
        return "touch_controller";
    } else if (interface_name.contains("index") || interface_name.contains("knuckles")) {
        return "index_controller";
    } else if (interface_name.contains("vive")) {
        return "vive_controller";
    } else if (interface_name.contains("wmr") || interface_name.contains("windows")) {
        return "wmr_controller";
    } else if (interface_name.contains("pico")) {
        return "pico_controller";
    }

    UtilityFunctions::push_warning(
            "InputProfiles: Could not detect controller profile from interface: ", interface_name);
    return String();
}

void InputProfiles::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_profile", "path"), &InputProfiles::load_profile);
    ClassDB::bind_method(D_METHOD("get_binding_path", "action_name"), &InputProfiles::get_binding_path);
    ClassDB::bind_method(D_METHOD("get_profile_name"), &InputProfiles::get_profile_name);
    ClassDB::bind_method(D_METHOD("get_interaction_profile"), &InputProfiles::get_interaction_profile);
    ClassDB::bind_static_method("InputProfiles", D_METHOD("detect_active_profile"), &InputProfiles::detect_active_profile);
}

} // namespace rtv_vr
