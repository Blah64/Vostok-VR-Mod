#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "xr_setup/xr_initializer.h"

using namespace godot;

void rtv_vr_mod_init(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    UtilityFunctions::print("[RTV-VR] Registering VR mod classes...");
    ClassDB::register_class<rtv_vr::XRInitializer>();
    UtilityFunctions::print("[RTV-VR] VR mod classes registered successfully.");
}

void rtv_vr_mod_terminate(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
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
