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

`ios-shell/main_shim.m` is the entry point SDL calls. It makes the app's Application Support
folder both `HOME` and the working directory (the bundle is read-only on a device and replaced by
every update, so nothing may be saved there), links `assets` in it to the bundle's, and runs
HashLink's main.

## The keyboard

A Heaps text field starts SDL text input when it takes focus, and that raises the iOS keyboard:
`main_shim.m` sets `SDL_HINT_ENABLE_SCREEN_KEYBOARD` so it also does in the Simulator, where SDL
sees the Mac's keyboard. SDL slides the whole view up when the keyboard would cover the field
being typed in (HashLink's binding pads the field's rect so its border clears the keyboard too).
In the Simulator, I/O > Keyboard > Toggle Software Keyboard shows it.

## The safe area

HashLink's SDL binding (libs/sdl/ios_safe_area.h in the hoseyjoe fork) shows Heaps the safe area
as if it were the window, so the app stays clear of the status bar, the Dynamic Island and the
home indicator; the bands outside take the clear colour. `sdl.Sdl.setHint("HL_IOS_SAFE_AREA", "0")`
before the window is made gives the app the whole screen.

## Files and the clipboard

`haxe.ui.backend.ios.FileDialog` is the iOS document picker (the Files sheet), with the calls of
heaps-android's `haxe.ui.backend.android.FileDialog`: `openToFile(mime, subdir, callback)` copies
the pick into `subdir` of the working directory and hands back its path; `saveAs(mime, name,
bytes, callback)` asks where to save. The natives are in `ios-shell/file_dialog.m`.

The clipboard needs nothing here: `hxd.System.getClipboardText` / `setClipboardText` go through
SDL, which uses the iOS pasteboard.

## Not done yet

- A touch way to copy and paste in a text field (there is no long-press menu), opening URLs,
  and heaps-android's other `haxeui_*` natives (back button, billing).
- Device builds, signing, icons, TestFlight.
