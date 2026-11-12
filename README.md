# heaps-ios

Turns the HashLink C (`-hl out/main.c`) output of a Heaps / HaxeUI-Heaps project into an iOS app
and runs it in the iOS Simulator. The iOS sibling of heaps-android. Simulator only so far: no
device build, signing or App Store packaging yet.

## Use

In the project's iOS hxml:

```
--library heaps-ios
-hl build/ios/c/main.c
-D no-compilation
--cmd haxelib run heaps-ios build/ios/c simulator com.example.MyApp "My App"
```

`haxelib run heaps-ios <hlcDir> [simulator] [appId] [label] [version=<s>] [build=<n>]`

Needs a Mac with Xcode, CMake 3.28+, and a HashLink 2.0+ checkout: `$HASHLINK_SRC`, or the one
the project's `hashlink` haxelib is a dev link into. With a project-local `.haxelib`, link the
library globally too (`haxelib --global dev heaps-ios <this folder>`): `haxelib run` looks there.

## What it does

`Run.hx` configures `ios-shell/` with CMake (`ios.toolchain.cmake`, arm64) into
`<project>/bin/ios-heaps/<sdk>/`. That one build compiles the generated C, HashLink (libhl and the
hdlls, static) and the libraries HashLink downloads (SDL3, libpng, libjpeg-turbo, vorbis,
Mbed TLS, libuv) into `HeapsApp.app`, with the project's `assets/` inside. It then boots an
iPhone simulator if none is running, installs the app and launches it.

`ios-shell/main_shim.m` is the entry point SDL calls: it points `HOME` at the app's Documents
folder and the working directory at the bundle, then runs HashLink's main.

## The safe area

HashLink's SDL binding (libs/sdl/ios_safe_area.h in the hoseyjoe fork) shows Heaps the safe area
as if it were the window, so the app stays clear of the status bar, the Dynamic Island and the
home indicator; the bands outside take the clear colour. `sdl.Sdl.setHint("HL_IOS_SAFE_AREA", "0")`
before the window is made gives the app the whole screen.

## Not done yet

- The on-screen keyboard, clipboard, file pickers and opening URLs (heaps-android's `haxeui_*`
  natives have no iOS side).
- Device builds, signing, icons, TestFlight.
