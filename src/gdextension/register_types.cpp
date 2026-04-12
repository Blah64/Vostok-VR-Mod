#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

// Core
#include "core/mod_orchestrator.h"
#include "core/scene_inspector.h"
#include "core/godot_api_bridge.h"

// XR Setup
#include "xr_setup/xr_initializer.h"
#include "xr_setup/xr_settings.h"

// Camera
// #include "camera/camera_override.h"
// #include "camera/head_tracking.h"
// #include "camera/comfort_options.h"

// Input
// #include "input/controller_manager.h"
// #include "input/action_mapper.h"
// #include "input/input_profiles.h"
// #include "input/haptics.h"

// Weapons
// #include "weapons/weapon_handler.h"
// #include "weapons/two_hand_grip.h"
// #include "weapons/weapon_detector.h"
// #include "weapons/recoil_feedback.h"

// UI
// #include "ui/ui_adapter.h"
// #include "ui/laser_pointer.h"
// #include "ui/virtual_keyboard.h"
// #include "ui/hud_anchor.h"

// Config
// #include "config/config_manager.h"

using namespace godot;

static rtv_vr::ModOrchestrator *s_orchestrator_singleton = nullptr;

void rtv_vr_mod_init(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    UtilityFunctions::print("[RTV-VR] Registering VR mod classes...");

    // Core classes
    ClassDB::register_class<rtv_vr::ModOrchestrator>();
    ClassDB::register_class<rtv_vr::SceneInspector>();
    // GodotApiBridge is static-only, no registration needed.

    // XR Setup classes
    ClassDB::register_class<rtv_vr::XRInitializer>();
    ClassDB::register_class<rtv_vr::XRSettings>();

    // Camera classes (uncomment as implemented)
    // ClassDB::register_class<rtv_vr::CameraOverride>();
    // ClassDB::register_class<rtv_vr::HeadTracking>();
    // ClassDB::register_class<rtv_vr::ComfortOptions>();

    // Input classes (uncomment as implemented)
    // ClassDB::register_class<rtv_vr::ControllerManager>();
    // ClassDB::register_class<rtv_vr::ActionMapper>();
    // ClassDB::register_class<rtv_vr::InputProfiles>();
    // ClassDB::register_class<rtv_vr::Haptics>();

    // Weapon classes (uncomment as implemented)
    // ClassDB::register_class<rtv_vr::WeaponHandler>();
    // ClassDB::register_class<rtv_vr::TwoHandGrip>();
    // ClassDB::register_class<rtv_vr::WeaponDetector>();
    // ClassDB::register_class<rtv_vr::RecoilFeedback>();

    // UI classes (uncomment as implemented)
    // ClassDB::register_class<rtv_vr::UIAdapter>();
    // ClassDB::register_class<rtv_vr::LaserPointer>();
    // ClassDB::register_class<rtv_vr::VRKeyboard>();  // VirtualKeyboard renamed to avoid Godot conflict
    // ClassDB::register_class<rtv_vr::HUDAnchor>();

    // Config classes (uncomment as implemented)
    // ClassDB::register_class<rtv_vr::ConfigManager>();

    // Create the ModOrchestrator singleton and register it as autoload
    s_orchestrator_singleton = memnew(rtv_vr::ModOrchestrator);
    Engine::get_singleton()->register_singleton("ModOrchestrator", s_orchestrator_singleton);

    UtilityFunctions::print("[RTV-VR] VR mod classes registered successfully.");
}

void rtv_vr_mod_terminate(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    UtilityFunctions::print("[RTV-VR] Shutting down VR mod...");

    // Unregister and free the orchestrator singleton
    if (s_orchestrator_singleton) {
        Engine::get_singleton()->unregister_singleton("ModOrchestrator");
        memdelete(s_orchestrator_singleton);
        s_orchestrator_singleton = nullptr;
    }

    UtilityFunctions::print("[RTV-VR] VR mod shut down.");
}

extern "C" {

GDExtensionBool GDE_EXPORT rtv_vr_mod_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        const GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(rtv_vr_mod_init);
    init_obj.register_terminator(rtv_vr_mod_terminate);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}

} // extern "C"
