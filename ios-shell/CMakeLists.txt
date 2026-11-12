# Builds <HLC_DIR>'s HashLink C into an iOS app bundle. Configured by ../Run.hx with
# ios.toolchain.cmake; HashLink (libhl and the hdlls, as static libraries) and what it links
# (SDL3, libpng, libjpeg-turbo, vorbis, Mbed TLS, libuv) are compiled from source here, the
# libraries downloaded by HashLink's own DOWNLOAD_DEPENDENCIES.
cmake_minimum_required(VERSION 3.28)
project(heaps-ios LANGUAGES C CXX OBJC)

set(HL_SOURCE "" CACHE PATH "A HashLink 2.0+ checkout (its libs/sdl is the SDL3 binding)")
set(HLC_DIR "" CACHE PATH "The folder haxe -hl <dir>/main.c wrote")
set(ASSETS_DIR "" CACHE PATH "The project's assets folder, copied into the bundle as assets/")
set(APP_ID "com.example.heapsios" CACHE STRING "Bundle identifier")
set(APP_NAME "Heaps App" CACHE STRING "The name under the icon")
set(APP_VERSION "1.0" CACHE STRING "CFBundleShortVersionString")
set(APP_BUILD "1" CACHE STRING "CFBundleVersion")

if(NOT EXISTS "${HL_SOURCE}/libs/sdl/sdl.c")
    message(FATAL_ERROR "HL_SOURCE (${HL_SOURCE}) is not a HashLink checkout")
endif()
if(NOT EXISTS "${HLC_DIR}/main.c")
    message(FATAL_ERROR "HLC_DIR (${HLC_DIR}) has no main.c: compile the project with -hl <dir>/main.c first")
endif()

# ---------------------------------------------------------------------------
# HashLink, static: an iOS app is one executable. No VM (there is no JIT on iOS: the app is
# HashLink C), no tests, no OpenAL.
# ---------------------------------------------------------------------------
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(DOWNLOAD_DEPENDENCIES ON CACHE BOOL "" FORCE)
set(WITH_VM OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(WITH_OPENAL OFF CACHE BOOL "" FORCE)
set(IOS_PLATFORM ON)
add_subdirectory("${HL_SOURCE}" hashlink EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# The app
# ---------------------------------------------------------------------------
# hl2c writes one .c per class in per-package folders; with HL_MAKE main.c does not include them.
file(GLOB_RECURSE HLC_SOURCES CONFIGURE_DEPENDS "${HLC_DIR}/*.c")

add_executable(app MACOSX_BUNDLE ${HLC_SOURCES} main_shim.m file_dialog.m)
set_target_properties(app PROPERTIES
    OUTPUT_NAME HeapsApp
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
)
configure_file(Info.plist.in "${CMAKE_CURRENT_BINARY_DIR}/Info.plist" @ONLY)

target_include_directories(app PRIVATE "${HLC_DIR}" "${HL_SOURCE}/src")
# The shim's Objective-C uses ARC (the picker's delegate is kept by a strong static).
set_source_files_properties(main_shim.m file_dialog.m PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_compile_definitions(app PRIVATE HL_MAKE)
# The generated C is not written for a human's warnings.
target_compile_options(app PRIVATE -w)
# hlc_main.c's main: main_shim.m's is the one SDL calls.
set_source_files_properties("${HLC_DIR}/main.c" PROPERTIES COMPILE_DEFINITIONS "main=heaps_ios_hl_main")

target_link_libraries(app PRIVATE
    libhl
    sdl.hdll fmt.hdll ui.hdll uv.hdll ssl.hdll sqlite.hdll fontsys.hdll heaps.hdll
    SDL3::SDL3
    "-framework UIKit" "-framework Foundation" "-framework OpenGLES" "-framework CoreText"
    "-framework UniformTypeIdentifiers"
)

if(ASSETS_DIR AND EXISTS "${ASSETS_DIR}")
    add_custom_command(TARGET app POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${ASSETS_DIR}" "$<TARGET_BUNDLE_CONTENT_DIR:app>/assets"
        COMMENT "Copying assets into the bundle")
endif()
