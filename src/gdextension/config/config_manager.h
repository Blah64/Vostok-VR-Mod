#ifndef RTV_VR_CONFIG_MANAGER_H
#define RTV_VR_CONFIG_MANAGER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace rtv_vr {

/// Loads and manages a JSON configuration file with hot-reload support.
///
/// Configuration is stored as a two-level Dictionary where top-level keys are
/// section names and their values are Dictionaries of key-value pairs.
///
/// Signals:
///   config_reloaded() - emitted when the file is reloaded from disk
class ConfigManager : public godot::RefCounted {
    GDCLASS(ConfigManager, godot::RefCounted)

public:
    ConfigManager() = default;
    ~ConfigManager() override = default;

    /// Load a JSON configuration file from the given path.
    /// Returns true on success.
    bool load(godot::String path);

    /// Save the current configuration back to the file it was loaded from.
    bool save();

    /// Save the current configuration to a specific path.
    bool save_to(godot::String path);

    /// Retrieve a value from the config.
    /// @param section   Top-level section name (e.g. "xr", "comfort").
    /// @param key       Key within the section.
    /// @param default_val Value returned if section/key is missing.
    godot::Variant get_value(godot::String section, godot::String key,
                             godot::Variant default_val) const;

    /// Set a value in the config (creates section if needed).
    void set_value(godot::String section, godot::String key,
                   godot::Variant value);

    /// Return an entire section as a Dictionary (empty if missing).
    godot::Dictionary get_section(godot::String section) const;

    /// Check whether the underlying file has been modified externally.
    /// If so, reload it and emit config_reloaded(). Returns true when a
    /// reload occurred.
    bool check_for_changes();

    /// Merge default values from default_config.json into the current
    /// config. Existing user values take priority.
    void apply_defaults();

protected:
    static void _bind_methods();

private:
    /// Internal helper: parse a JSON string into config_.
    bool parse_json(const godot::String& json_text);

    /// Internal helper: serialize config_ to a JSON string.
    godot::String serialize_json() const;

    godot::Dictionary config_;
    godot::String     config_path_;
    uint64_t          last_modified_time_ = 0;
};

} // namespace rtv_vr

#endif // RTV_VR_CONFIG_MANAGER_H
