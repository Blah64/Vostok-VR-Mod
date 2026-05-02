add_library(rtv_vr_mod SHARED
    register_types.cpp
    xr_setup/xr_initializer.cpp
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
