#ifndef RTV_VR_XR_SETTINGS_H
#define RTV_VR_XR_SETTINGS_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace rtv_vr {

class XRSettings : public godot::RefCounted {
    GDCLASS(XRSettings, godot::RefCounted)

public:
    XRSettings() = default;
    ~XRSettings() override = default;

    /// Apply all XR-related settings from a config dictionary.
    /// Recognized keys: "render_scale", "refresh_rate", "foveation", "world_scale".
    void apply_from_config(const godot::Dictionary &p_config);

    /// Set the viewport render target size multiplier.
    void set_render_scale(float p_scale);

    /// Request a display refresh rate from the XR runtime.
    void set_refresh_rate(int p_rate);

    /// Set the foveated rendering level (0 = off, 1-3 = low/medium/high).
    void set_foveation(int p_level);

    /// Set the XR world scale (affects how large the world appears).
    void set_world_scale(float p_scale);

    /// Query the XR runtime for the recommended render target size multiplier.
    float get_recommended_render_scale() const;

protected:
    static void _bind_methods();
};

} // namespace rtv_vr

#endif // RTV_VR_XR_SETTINGS_H
