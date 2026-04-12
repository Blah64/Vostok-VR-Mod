add_library(rtv_vr_bootstrap SHARED
    dllmain.cpp
    command_line_patch.cpp
    extension_deployer.cpp
    vulkan_hook_installer.cpp
)

target_include_directories(rtv_vr_bootstrap PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${Vulkan_INCLUDE_DIRS}
)

target_link_libraries(rtv_vr_bootstrap PRIVATE
    minhook
    spdlog::spdlog
    nlohmann_json::nlohmann_json
)

rtv_vr_set_warnings(rtv_vr_bootstrap)

set_target_properties(rtv_vr_bootstrap PROPERTIES
    OUTPUT_NAME "rtv_vr_bootstrap"
    PREFIX ""
)
