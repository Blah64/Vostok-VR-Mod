add_library(rtv_vr_vulkan STATIC
    vk_dispatch_table.cpp
    vk_hooks.cpp
    hud_reprojector.cpp
    perf_overlay.cpp
)

target_include_directories(rtv_vr_vulkan PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${Vulkan_INCLUDE_DIRS}
)

target_link_libraries(rtv_vr_vulkan PRIVATE
    spdlog::spdlog
    minhook
)

rtv_vr_set_warnings(rtv_vr_vulkan)

# Link into bootstrap DLL
target_link_libraries(rtv_vr_bootstrap PRIVATE rtv_vr_vulkan)
