function(rpcs3_link_moltenvk target moltenvk_root)
    if(NOT TARGET ${target})
        message(FATAL_ERROR "Unknown target passed to rpcs3_link_moltenvk: ${target}")
    endif()
    if(NOT moltenvk_root)
        message(FATAL_ERROR "RPCS3_IOS_MOLTENVK_ROOT is required")
    endif()

    set(_xcframework "${moltenvk_root}/MoltenVK.xcframework")
    set(_framework "${_xcframework}/ios-arm64/MoltenVK.framework")
    set(_binary "${_framework}/MoltenVK")
    set(_include "${moltenvk_root}/include")

    foreach(_required IN ITEMS
        "${_binary}"
        "${_include}/vulkan/vulkan.h"
        "${_include}/MoltenVK/vk_mvk_moltenvk.h")
        if(NOT EXISTS "${_required}")
            message(FATAL_ERROR "Missing MoltenVK input: ${_required}")
        endif()
    endforeach()

    if(NOT TARGET MoltenVK::MoltenVK)
        add_library(MoltenVK::MoltenVK STATIC IMPORTED GLOBAL)
        set_target_properties(MoltenVK::MoltenVK PROPERTIES
            IMPORTED_LOCATION "${_binary}"
            INTERFACE_INCLUDE_DIRECTORIES "${_include};${_framework}/Headers"
        )
    endif()

    target_compile_definitions(${target} PRIVATE
        RPCS3_IOS_HAS_MOLTENVK=1
        VK_USE_PLATFORM_METAL_EXT=1
    )
    target_link_libraries(${target} PRIVATE
        MoltenVK::MoltenVK
        "-framework Metal"
        "-framework Foundation"
        "-framework QuartzCore"
        "-framework CoreGraphics"
        "-framework IOSurface"
    )
endfunction()
