#include "mod_orchestrator.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "scene_inspector.h"
#include "godot_api_bridge.h"
#include "../xr_setup/xr_initializer.h"

using namespace godot;

namespace rtv_vr {

ModOrchestrator *ModOrchestrator::s_singleton = nullptr;

ModOrchestrator::ModOrchestrator() {
    if (s_singleton == nullptr) {
        s_singleton = this;
    }
}

ModOrchestrator::~ModOrchestrator() {
    if (s_singleton == this) {
        s_singleton = nullptr;
    }
}

ModOrchestrator *ModOrchestrator::get_singleton() {
    return s_singleton;
}

void ModOrchestrator::_bind_methods() {
    // State property
    ClassDB::bind_method(D_METHOD("get_state"), &ModOrchestrator::get_state);
    ClassDB::bind_method(D_METHOD("get_state_name"), &ModOrchestrator::get_state_name);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "state", PROPERTY_HINT_ENUM,
                     "Uninitialized,WaitingForSceneTree,InitializingXR,ScanningScene,"
                     "InstallingCameraRig,InstallingControllers,AdaptingUI,Running,Error"),
            "", "get_state");

    // Scene change callback
    ClassDB::bind_method(D_METHOD("on_scene_tree_changed"), &ModOrchestrator::on_scene_tree_changed);

    // Signals
    ADD_SIGNAL(MethodInfo("state_changed",
            PropertyInfo(Variant::INT, "new_state"),
            PropertyInfo(Variant::INT, "old_state")));
    ADD_SIGNAL(MethodInfo("initialization_complete"));
    ADD_SIGNAL(MethodInfo("error_occurred", PropertyInfo(Variant::STRING, "message")));

    // Enum constants
    BIND_ENUM_CONSTANT(STATE_UNINITIALIZED);
    BIND_ENUM_CONSTANT(STATE_WAITING_FOR_SCENE_TREE);
    BIND_ENUM_CONSTANT(STATE_INITIALIZING_XR);
    BIND_ENUM_CONSTANT(STATE_SCANNING_SCENE);
    BIND_ENUM_CONSTANT(STATE_INSTALLING_CAMERA_RIG);
    BIND_ENUM_CONSTANT(STATE_INSTALLING_CONTROLLERS);
    BIND_ENUM_CONSTANT(STATE_ADAPTING_UI);
    BIND_ENUM_CONSTANT(STATE_RUNNING);
    BIND_ENUM_CONSTANT(STATE_ERROR);
}

void ModOrchestrator::_ready() {
    if (Engine::get_singleton()->is_editor_hint()) {
        return;
    }

    UtilityFunctions::print("[RTV-VR] ModOrchestrator ready, starting state machine.");
    set_process(true);

    // Begin state progression
    State old = m_state;
    m_state = STATE_WAITING_FOR_SCENE_TREE;
    emit_signal("state_changed", (int)m_state, (int)old);

    // Connect to scene tree change signal if available
    SceneTree *tree = get_tree();
    if (tree) {
        tree->connect("node_added", Callable(this, "on_scene_tree_changed"));
    }
}

void ModOrchestrator::_process(double p_delta) {
    if (Engine::get_singleton()->is_editor_hint()) {
        return;
    }

    // Advance the state machine
    advance_state();

    // Update active subsystems each frame when running
    if (m_state == STATE_RUNNING) {
        // Subsystem per-frame updates go here as they are implemented.
        // Example:
        // if (m_camera_override) m_camera_override->update(p_delta);
        // if (m_controller_manager) m_controller_manager->update(p_delta);
        // if (m_weapon_handler) m_weapon_handler->update(p_delta);
    }
}

void ModOrchestrator::advance_state() {
    switch (m_state) {
        case STATE_UNINITIALIZED:
            // Waiting for _ready()
            break;

        case STATE_WAITING_FOR_SCENE_TREE: {
            SceneTree *tree = get_tree();
            if (tree && tree->get_current_scene()) {
                UtilityFunctions::print("[RTV-VR] Scene tree available, initializing XR...");
                State old = m_state;
                m_state = STATE_INITIALIZING_XR;
                emit_signal("state_changed", (int)m_state, (int)old);
            }
            break;
        }

        case STATE_INITIALIZING_XR: {
            if (m_xr_initializer.is_null()) {
                m_xr_initializer.instantiate();
            }
            XRInitializer::Result result = m_xr_initializer->activate_openxr();
            if (result == XRInitializer::RESULT_SUCCESS || result == XRInitializer::RESULT_ALREADY_ACTIVE) {
                UtilityFunctions::print("[RTV-VR] XR initialized, scanning scene...");
                State old = m_state;
                m_state = STATE_SCANNING_SCENE;
                emit_signal("state_changed", (int)m_state, (int)old);
            } else {
                enter_error(String("XR initialization failed with code: ") + String::num_int64((int)result));
            }
            break;
        }

        case STATE_SCANNING_SCENE: {
            SceneTree *tree = get_tree();
            if (!tree || !tree->get_current_scene()) {
                break;
            }

            Ref<SceneInspector> inspector;
            inspector.instantiate();
            Node *root = tree->get_current_scene();

            Camera3D *camera = inspector->find_camera(root);
            if (camera) {
                UtilityFunctions::print("[RTV-VR] Found game camera: ", camera->get_path());
            } else {
                UtilityFunctions::print("[RTV-VR] Warning: No Camera3D found in scene.");
            }

            UtilityFunctions::print("[RTV-VR] Scene scan complete, installing camera rig...");
            State old = m_state;
            m_state = STATE_INSTALLING_CAMERA_RIG;
            emit_signal("state_changed", (int)m_state, (int)old);
            break;
        }

        case STATE_INSTALLING_CAMERA_RIG: {
            // TODO: Create CameraOverride and HeadTracking subsystems
            UtilityFunctions::print("[RTV-VR] Camera rig installed (stub), installing controllers...");
            State old = m_state;
            m_state = STATE_INSTALLING_CONTROLLERS;
            emit_signal("state_changed", (int)m_state, (int)old);
            break;
        }

        case STATE_INSTALLING_CONTROLLERS: {
            // TODO: Create ControllerManager subsystem
            UtilityFunctions::print("[RTV-VR] Controllers installed (stub), adapting UI...");
            State old = m_state;
            m_state = STATE_ADAPTING_UI;
            emit_signal("state_changed", (int)m_state, (int)old);
            break;
        }

        case STATE_ADAPTING_UI: {
            // TODO: Create UIAdapter subsystem
            UtilityFunctions::print("[RTV-VR] UI adapted (stub), entering running state.");
            State old = m_state;
            m_state = STATE_RUNNING;
            emit_signal("state_changed", (int)m_state, (int)old);
            emit_signal("initialization_complete");
            break;
        }

        case STATE_RUNNING:
            // Steady state -- nothing to advance
            break;

        case STATE_ERROR:
            // Terminal state
            set_process(false);
            break;
    }
}

void ModOrchestrator::enter_error(const String &p_message) {
    UtilityFunctions::printerr("[RTV-VR] ERROR: ", p_message);
    State old = m_state;
    m_state = STATE_ERROR;
    m_error_message = p_message;
    emit_signal("state_changed", (int)m_state, (int)old);
    emit_signal("error_occurred", p_message);
}

ModOrchestrator::State ModOrchestrator::get_state() const {
    return m_state;
}

String ModOrchestrator::get_state_name() const {
    switch (m_state) {
        case STATE_UNINITIALIZED:           return "Uninitialized";
        case STATE_WAITING_FOR_SCENE_TREE:  return "WaitingForSceneTree";
        case STATE_INITIALIZING_XR:         return "InitializingXR";
        case STATE_SCANNING_SCENE:          return "ScanningScene";
        case STATE_INSTALLING_CAMERA_RIG:   return "InstallingCameraRig";
        case STATE_INSTALLING_CONTROLLERS:  return "InstallingControllers";
        case STATE_ADAPTING_UI:             return "AdaptingUI";
        case STATE_RUNNING:                 return "Running";
        case STATE_ERROR:                   return "Error";
        default:                            return "Unknown";
    }
}

void ModOrchestrator::on_scene_tree_changed() {
    if (m_state == STATE_RUNNING) {
        UtilityFunctions::print("[RTV-VR] Scene tree changed, re-scanning...");
        State old = m_state;
        m_state = STATE_SCANNING_SCENE;
        emit_signal("state_changed", (int)m_state, (int)old);
    }
}

} // namespace rtv_vr
