# The whole build, HashLink's downloaded libraries included (HashLink hands CMAKE_TOOLCHAIN_FILE on
# to them), is for iOS on arm64: a device, or the simulator on an Apple Silicon Mac.
# Run.hx says which through the environment (a toolchain file is read again by every try_compile
# and every external project, none of which see this build's cache): HEAPS_IOS_SDK is
# iphonesimulator (the default) or iphoneos.
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "" FORCE)
if(DEFINED ENV{HEAPS_IOS_SDK} AND NOT "$ENV{HEAPS_IOS_SDK}" STREQUAL "")
    set(CMAKE_OSX_SYSROOT $ENV{HEAPS_IOS_SDK} CACHE STRING "" FORCE)
else()
    set(CMAKE_OSX_SYSROOT iphonesimulator CACHE STRING "" FORCE)
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0 CACHE STRING "" FORCE)
# Nothing from the Mac's own Homebrew may be found for an iOS link.
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
