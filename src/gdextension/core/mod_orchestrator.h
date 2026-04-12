#ifndef RTV_VR_MOD_ORCHESTRATOR_H
#define RTV_VR_MOD_ORCHESTRATOR_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

namespace rtv_vr {

class XRInitializer;
class XRSettings;

class ModOrchestrator : public godot::Node {
    GDCLASS(ModOrchestrator, godot::Node)

public:
    enum State {
        STATE_UNINITIALIZED,
        STATE_WAITING_FOR_SCENE_TREE,
        STATE_INITIALIZING_XR,
        STATE_SCANNING_SCENE,
        STATE_INSTALLING_CAMERA_RIG,
        STATE_INSTALLING_CONTROLLERS,
        STATE_ADAPTING_UI,
        STATE_RUNNING,
        STATE_ERROR,
    };

    ModOrchestrator();
    ~ModOrchestrator() override;

    static ModOrchestrator *get_singleton();

    // Godot lifecycle
    void _ready() override;
    void _process(double p_delta) override;

    // State machine
    State get_state() const;
    godot::String get_state_name() const;

    // Scene change handler
    void on_scene_tree_changed();

protected:
    static void _bind_methods();

private:
    void advance_state();
    void enter_error(const godot::String &p_message);

    static ModOrchestrator *s_singleton;

    State m_state = STATE_UNINITIALIZED;
    godot::String m_error_message;

    // Subsystem pointers (created during state progression)
    godot::Ref<XRInitializer> m_xr_initializer;
    // Placeholders for subsystems to be implemented in other source files:
    // CameraOverride *m_camera_override = nullptr;
    // ControllerManager *m_controller_manager = nullptr;
    // UIAdapter *m_ui_adapter = nullptr;
    // WeaponHandler *m_weapon_handler = nullptr;
    // ConfigManager *m_config_manager = nullptr;
};

} // namespace rtv_vr

VARIANT_ENUM_CAST(rtv_vr::ModOrchestrator::State)

#endif // RTV_VR_MOD_ORCHESTRATOR_H
