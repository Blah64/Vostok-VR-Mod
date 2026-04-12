# Shared compiler warning flags for all targets
function(rtv_vr_set_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE
            /W4
            /wd4100  # unreferenced formal parameter
            /wd4201  # nonstandard extension: nameless struct/union
            /wd4324  # structure was padded due to alignment specifier
        )
        target_compile_definitions(${target} PRIVATE
            _CRT_SECURE_NO_WARNINGS
            NOMINMAX
            WIN32_LEAN_AND_MEAN
        )
    else()
        target_compile_options(${target} PRIVATE
            -Wall -Wextra -Wpedantic
            -Wno-unused-parameter
        )
    endif()
endfunction()
