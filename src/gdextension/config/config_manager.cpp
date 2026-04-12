#include "config_manager.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

// ---------------------------------------------------------------------------
// GDExtension binding
// ---------------------------------------------------------------------------

void ConfigManager::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load", "path"), &ConfigManager::load);
    ClassDB::bind_method(D_METHOD("save"), &ConfigManager::save);
    ClassDB::bind_method(D_METHOD("save_to", "path"), &ConfigManager::save_to);
    ClassDB::bind_method(D_METHOD("get_value", "section", "key", "default_val"),
                         &ConfigManager::get_value);
    ClassDB::bind_method(D_METHOD("set_value", "section", "key", "value"),
                         &ConfigManager::set_value);
    ClassDB::bind_method(D_METHOD("get_section", "section"),
                         &ConfigManager::get_section);
    ClassDB::bind_method(D_METHOD("check_for_changes"),
                         &ConfigManager::check_for_changes);
    ClassDB::bind_method(D_METHOD("apply_defaults"),
                         &ConfigManager::apply_defaults);

    ADD_SIGNAL(MethodInfo("config_reloaded"));
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

bool ConfigManager::load(String path) {
    config_path_ = path;

    if (!FileAccess::file_exists(path)) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: File not found: ", path);
        return false;
    }

    Ref<FileAccess> file = FileAccess::open(path, FileAccess::READ);
    if (file.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: Cannot open: ", path,
                                    " (error ", FileAccess::get_open_error(), ")");
        return false;
    }

    String json_text = file->get_as_text();
    file.unref();

    if (!parse_json(json_text)) {
        return false;
    }

    last_modified_time_ = FileAccess::get_modified_time(path);
    UtilityFunctions::print("[RTV-VR] ConfigManager: Loaded config from ", path);
    return true;
}

// ---------------------------------------------------------------------------
// Saving
// ---------------------------------------------------------------------------

bool ConfigManager::save() {
    if (config_path_.is_empty()) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: No config path set, use save_to()");
        return false;
    }
    return save_to(config_path_);
}

bool ConfigManager::save_to(String path) {
    Ref<FileAccess> file = FileAccess::open(path, FileAccess::WRITE);
    if (file.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: Cannot write to: ", path,
                                    " (error ", FileAccess::get_open_error(), ")");
        return false;
    }

    String json_text = serialize_json();
    file->store_string(json_text);
    file.unref();

    last_modified_time_ = FileAccess::get_modified_time(path);
    UtilityFunctions::print("[RTV-VR] ConfigManager: Saved config to ", path);
    return true;
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

Variant ConfigManager::get_value(String section, String key,
                                 Variant default_val) const {
    if (!config_.has(section)) {
        return default_val;
    }

    Variant section_var = config_[section];
    if (section_var.get_type() != Variant::DICTIONARY) {
        return default_val;
    }

    Dictionary section_dict = section_var;
    if (!section_dict.has(key)) {
        return default_val;
    }

    return section_dict[key];
}

void ConfigManager::set_value(String section, String key, Variant value) {
    Dictionary section_dict;

    if (config_.has(section)) {
        Variant existing = config_[section];
        if (existing.get_type() == Variant::DICTIONARY) {
            section_dict = existing;
        }
    }

    section_dict[key] = value;
    config_[section] = section_dict;
}

Dictionary ConfigManager::get_section(String section) const {
    if (!config_.has(section)) {
        return Dictionary();
    }

    Variant section_var = config_[section];
    if (section_var.get_type() != Variant::DICTIONARY) {
        return Dictionary();
    }

    return section_var;
}

// ---------------------------------------------------------------------------
// Hot-reload
// ---------------------------------------------------------------------------

bool ConfigManager::check_for_changes() {
    if (config_path_.is_empty()) {
        return false;
    }

    if (!FileAccess::file_exists(config_path_)) {
        return false;
    }

    uint64_t current_mtime = FileAccess::get_modified_time(config_path_);
    if (current_mtime == last_modified_time_) {
        return false;
    }

    UtilityFunctions::print("[RTV-VR] ConfigManager: File changed on disk, reloading...");

    Ref<FileAccess> file = FileAccess::open(config_path_, FileAccess::READ);
    if (file.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: Failed to reopen config file");
        return false;
    }

    String json_text = file->get_as_text();
    file.unref();

    if (!parse_json(json_text)) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: Reload parse failed, keeping old config");
        return false;
    }

    last_modified_time_ = current_mtime;
    emit_signal("config_reloaded");
    UtilityFunctions::print("[RTV-VR] ConfigManager: Config reloaded successfully");
    return true;
}

// ---------------------------------------------------------------------------
// Defaults merging
// ---------------------------------------------------------------------------

void ConfigManager::apply_defaults() {
    // Look for default_config.json next to the loaded config file.
    String defaults_path;
    if (!config_path_.is_empty()) {
        int last_slash = config_path_.rfind("/");
        if (last_slash < 0) {
            last_slash = config_path_.rfind("\\");
        }
        if (last_slash >= 0) {
            defaults_path = config_path_.substr(0, last_slash + 1) + "default_config.json";
        } else {
            defaults_path = "default_config.json";
        }
    } else {
        defaults_path = "res://default_config.json";
    }

    if (!FileAccess::file_exists(defaults_path)) {
        UtilityFunctions::print("[RTV-VR] ConfigManager: No defaults file found at ", defaults_path);
        return;
    }

    Ref<FileAccess> file = FileAccess::open(defaults_path, FileAccess::READ);
    if (file.is_null()) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: Cannot open defaults: ", defaults_path);
        return;
    }

    String json_text = file->get_as_text();
    file.unref();

    Variant parsed = JSON::parse_string(json_text);
    if (parsed.get_type() != Variant::DICTIONARY) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: Defaults file is not a valid JSON object");
        return;
    }

    Dictionary defaults = parsed;

    // Merge: for each section in defaults, add keys that are missing in config_.
    Array sections = defaults.keys();
    for (int i = 0; i < sections.size(); ++i) {
        String section_name = sections[i];

        Variant def_section_var = defaults[section_name];
        if (def_section_var.get_type() != Variant::DICTIONARY) {
            continue;
        }
        Dictionary def_section = def_section_var;

        Dictionary cfg_section;
        if (config_.has(section_name)) {
            Variant existing = config_[section_name];
            if (existing.get_type() == Variant::DICTIONARY) {
                cfg_section = existing;
            }
        }

        Array def_keys = def_section.keys();
        for (int j = 0; j < def_keys.size(); ++j) {
            String key = def_keys[j];
            if (!cfg_section.has(key)) {
                cfg_section[key] = def_section[key];
            }
        }

        config_[section_name] = cfg_section;
    }

    UtilityFunctions::print("[RTV-VR] ConfigManager: Defaults merged from ", defaults_path);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

bool ConfigManager::parse_json(const String& json_text) {
    Variant parsed = JSON::parse_string(json_text);
    if (parsed.get_type() != Variant::DICTIONARY) {
        UtilityFunctions::printerr("[RTV-VR] ConfigManager: JSON root is not an object");
        return false;
    }

    config_ = parsed;
    return true;
}

String ConfigManager::serialize_json() const {
    // Use JSON::stringify for pretty-printed output.
    return JSON::stringify(config_, "  ");
}

} // namespace rtv_vr
