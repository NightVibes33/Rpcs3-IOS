function(rpcs3_link_moltenvk target moltenvk_root)
    if(NOT TARGET ${target})
        message(FATAL_ERROR "Unknown target passed to rpcs3_link_moltenvk: ${target}")
    endif()
    if(NOT moltenvk_root)
        message(FATAL_ERROR "RPCS3_IOS_MOLTENVK_ROOT is required")
    endif()

    set(_xcframework "${moltenvk_root}/MoltenVK.xcframework")
    set(_include "${moltenvk_root}/include")
    set(_binary "")

    if(EXISTS "${moltenvk_root}/device-binary-path.txt")
        file(STRINGS "${moltenvk_root}/device-binary-path.txt" _relative_binary LIMIT_COUNT 1)
        string(STRIP "${_relative_binary}" _relative_binary)
        if(NOT _relative_binary STREQUAL "")
            set(_binary "${moltenvk_root}/${_relative_binary}")
        endif()
    endif()

    if(NOT EXISTS "${_binary}")
        file(GLOB_RECURSE _moltenvk_candidates LIST_DIRECTORIES false
            "${_xcframework}/*/MoltenVK.framework/MoltenVK")
        foreach(_candidate IN LISTS _moltenvk_candidates)
            string(TOLOWER "${_candidate}" _candidate_lower)
            if(_candidate_lower MATCHES "simulator|maccatalyst")
                continue()
            endif()
            if(_candidate MATCHES "/ios-[^/]+/MoltenVK\\.framework/MoltenVK$")
                set(_binary "${_candidate}")
                break()
            endif()
        endforeach()
    endif()

    if(NOT EXISTS "${_binary}")
        message(FATAL_ERROR "No arm64 iOS MoltenVK framework binary was found under ${_xcframework}")
    endif()
    get_filename_component(_framework "${_binary}" DIRECTORY)

    foreach(_required IN ITEMS
        "${_binary}"
        "${_include}/vulkan/vulkan.h"
        "${_include}/MoltenVK/vk_mvk_moltenvk.h")
        if(NOT EXISTS "${_required}")
            message(FATAL_ERROR "Missing MoltenVK input: ${_required}")
        endif()
    endforeach()

    message(STATUS "RPCS3 iOS: linking MoltenVK device slice ${_binary}")
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
