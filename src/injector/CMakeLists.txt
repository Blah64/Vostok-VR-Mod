add_executable(rtv_vr_injector
    main.cpp
    process_utils.cpp
)

target_include_directories(rtv_vr_injector PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

target_link_libraries(rtv_vr_injector PRIVATE
    spdlog::spdlog
)

# Ensure proper CRT linkage
set_property(TARGET rtv_vr_injector PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
)

rtv_vr_set_warnings(rtv_vr_injector)

set_target_properties(rtv_vr_injector PROPERTIES
    OUTPUT_NAME "rtv_vr_injector"
)
