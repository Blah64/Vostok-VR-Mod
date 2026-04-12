#ifndef RTV_VR_XR_INITIALIZER_H
#define RTV_VR_XR_INITIALIZER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/xr_interface.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace rtv_vr {

class XRInitializer : public godot::RefCounted {
    GDCLASS(XRInitializer, godot::RefCounted)

public:
    enum Result {
        RESULT_SUCCESS,
        RESULT_NO_INTERFACE,
        RESULT_INIT_FAILED,
        RESULT_ALREADY_ACTIVE,
    };

    XRInitializer() = default;
    ~XRInitializer() override = default;

    /// Activates the OpenXR interface. Returns a Result code.
    Result activate_openxr();

    /// Apply XR settings from a config dictionary (render_scale, refresh_rate, foveation).
    void apply_settings(const godot::Dictionary &p_config);

    /// Returns true if the XR interface is currently initialized and active.
    bool is_xr_active() const;

protected:
    static void _bind_methods();

private:
    // Signal handlers for XR session state
    void _on_session_begun();
    void _on_session_stopping();
    void _on_session_focussed();

    godot::Ref<godot::XRInterface> m_xr_interface;
};

} // namespace rtv_vr

VARIANT_ENUM_CAST(rtv_vr::XRInitializer::Result)

#endif // RTV_VR_XR_INITIALIZER_H
