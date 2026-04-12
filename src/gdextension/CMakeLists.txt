add_library(rtv_vr_mod SHARED
    register_types.cpp
    core/mod_orchestrator.cpp
    core/scene_inspector.cpp
    core/godot_api_bridge.cpp
    xr_setup/xr_initializer.cpp
    xr_setup/xr_settings.cpp
    camera/camera_override.cpp
    camera/head_tracking.cpp
    camera/comfort_options.cpp
    input/controller_manager.cpp
    input/action_mapper.cpp
    input/input_profiles.cpp
    input/haptics.cpp
    weapons/weapon_handler.cpp
    weapons/two_hand_grip.cpp
    weapons/weapon_detector.cpp
    weapons/recoil_feedback.cpp
    ui/ui_adapter.cpp
    ui/laser_pointer.cpp
    ui/virtual_keyboard.cpp
    ui/hud_anchor.cpp
    config/config_manager.cpp
)

target_include_directories(rtv_vr_mod PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/src/gdextension
)

target_link_libraries(rtv_vr_mod PRIVATE
    godot-cpp.template_debug
    spdlog::spdlog
    nlohmann_json::nlohmann_json
)

rtv_vr_set_warnings(rtv_vr_mod)

set_target_properties(rtv_vr_mod PROPERTIES
    OUTPUT_NAME "librtv_vr_mod.windows.x86_64"
    PREFIX ""
    SUFFIX ".dll"
)
