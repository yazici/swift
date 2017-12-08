set(swift_platform_name)
set(swift_platform_flags)
set(swift_platform_sources
    Platform.swift
    TiocConstants.swift
    tgmath.swift.gyb)

add_swift_library(swiftDarwin ${SWIFT_STDLIB_LIBRARY_BUILD_TYPES} IS_SDK_OVERLAY
    Darwin.swift.gyb
    ${swift_platform_sources}
    POSIXError.swift
    MachError.swift

    SWIFT_COMPILE_FLAGS -Xfrontend -disable-objc-attr-requires-foundation-module "${SWIFT_RUNTIME_SWIFT_COMPILE_FLAGS}"
    LINK_FLAGS "${SWIFT_RUNTIME_SWIFT_LINK_FLAGS}"
    TARGET_SDKS ALL_APPLE_PLATFORMS
    API_NOTES_NON_OVERLAY)

add_swift_library(swiftGlibc ${SWIFT_STDLIB_LIBRARY_BUILD_TYPES} IS_SDK_OVERLAY
    Glibc.swift.gyb
    ${swift_platform_sources}

    SWIFT_COMPILE_FLAGS "${SWIFT_RUNTIME_SWIFT_COMPILE_FLAGS}"
    LINK_FLAGS "${SWIFT_RUNTIME_SWIFT_LINK_FLAGS}"
    TARGET_SDKS ANDROID CYGWIN FREEBSD LINUX HAIKU
    DEPENDS glibc_modulemap)

add_swift_library(swiftMSVCRT ${SWIFT_STDLIB_LIBRARY_BUILD_TYPES} IS_SDK_OVERLAY
    msvcrt.swift
    ${swift_platform_sources}

    SWIFT_COMPILE_FLAGS "${SWIFT_RUNTIME_SWIFT_COMPILE_FLAGS}"
    LINK_FLAGS "${SWIFT_RUNTIME_SWIFT_LINK_FLAGS}"
    TARGET_SDKS WINDOWS)

set(glibc_modulemap_target_list)
foreach(sdk ${SWIFT_SDKS})
  if(NOT "${sdk}" STREQUAL "LINUX" AND
     NOT "${sdk}" STREQUAL "FREEBSD" AND
     NOT "${sdk}" STREQUAL "ANDROID" AND
     NOT "${sdk}" STREQUAL "CYGWIN" AND
     NOT "${sdk}" STREQUAL "HAIKU")
    continue()
  endif()

  foreach(arch ${SWIFT_SDK_${sdk}_ARCHITECTURES})
    set(arch_subdir "${SWIFT_SDK_${sdk}_LIB_SUBDIR}/${arch}")
    set(module_dir "${SWIFTLIB_DIR}/${arch_subdir}")

    set(glibc_modulemap_source "glibc.modulemap.gyb")
    set(glibc_modulemap_out "${module_dir}/glibc.modulemap")

    # Configure the module map based on the target. Each platform needs to
    # reference different headers, based on what's available in their glibc.
    # This is the 'glibc.modulemap' in the 'resource-dir', so
    # it's the one we'll look at during the build process.
    handle_gyb_source_single(glibc_modulemap_target
        SOURCE "${glibc_modulemap_source}"
        OUTPUT "${glibc_modulemap_out}"
        FLAGS
            "-DCMAKE_SDK=${sdk}"
            "-DGLIBC_INCLUDE_PATH=\"<system-include>\""
            "-DGLIBC_ARCH_INCLUDE_PATH=\"<system-arch-include>\"")

    list(APPEND glibc_modulemap_target_list ${glibc_modulemap_target})
  endforeach()
endforeach()
add_custom_target(glibc_modulemap DEPENDS ${glibc_modulemap_target_list})
