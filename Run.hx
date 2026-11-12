package;

import sys.FileSystem;
import sys.io.Process;
import haxe.io.Path;

/**
 * `haxelib run heaps-ios <hlcDir> [simulator] [appId] [label] [version=<s>] [build=<n>] <projectFolder>`
 * (haxelib appends the project folder), usually a --cmd at the end of the project's iOS hxml.
 *
 *   1. Configures ios-shell/ with CMake into <project>/bin/ios-heaps/<sdk>/: the generated
 *      HashLink C from <hlcDir>, HashLink itself and what it links, all for iOS arm64.
 *   2. Builds HeapsApp.app, with <project>/assets inside it.
 *   3. simulator: boots an iPhone simulator if none is running, installs the app and launches it.
 *
 * HashLink's source is $HASHLINK_SRC, or the checkout the project's `hashlink` haxelib is a dev
 * link into (<checkout>/other/haxelib).
 */
class Run {
    static function main() {
        var args = Sys.args();
        // haxelib runs this from the library's folder and passes the caller's as the last argument.
        var libRoot = Sys.getCwd();
        var projectFolder = args.pop();
        if (projectFolder == null || !FileSystem.isDirectory(projectFolder)) fail("no project folder (run through `haxelib run heaps-ios`)");
        Sys.setCwd(projectFolder);

        var positional = [], version = "1.0", build = "1";
        for (a in args) {
            if (StringTools.startsWith(a, "version=")) version = a.substr(8);
            else if (StringTools.startsWith(a, "build=")) build = a.substr(6);
            else positional.push(a);
        }
        var hlcDir = positional[0];
        var target = positional.length > 1 ? positional[1] : "simulator";
        var appId = positional.length > 2 ? positional[2] : "com.example.heapsios";
        var label = positional.length > 3 ? positional[3] : "Heaps App";
        if (hlcDir == null) fail("usage: haxelib run heaps-ios <hlcDir> [simulator] [appId] [label]");
        if (target != "simulator") fail('target "$target": only `simulator` is built so far');
        if (Sys.systemName() != "Mac") fail("an iOS build needs a Mac with Xcode");
        hlcDir = FileSystem.absolutePath(hlcDir);
        if (!FileSystem.exists(Path.join([hlcDir, "main.c"]))) fail('$hlcDir has no main.c');

        var hlSource = hashlinkSource();
        var sdk = "iphonesimulator";
        Sys.putEnv("HEAPS_IOS_SDK", sdk);
        var shell = Path.join([libRoot, "ios-shell"]);
        var buildDir = Path.join([FileSystem.absolutePath("bin/ios-heaps"), sdk]);
        var assets = FileSystem.absolutePath("assets");

        Sys.println('--- heaps-ios: configuring ($sdk, HashLink at $hlSource) ---');
        run("cmake", [
            "-S", shell, "-B", buildDir, "-G", "Unix Makefiles",
            "-DCMAKE_TOOLCHAIN_FILE=" + Path.join([shell, "ios.toolchain.cmake"]),
            "-DCMAKE_BUILD_TYPE=Release",
            "-DHL_SOURCE=" + hlSource,
            "-DHLC_DIR=" + hlcDir,
            "-DASSETS_DIR=" + (FileSystem.exists(assets) ? assets : ""),
            "-DAPP_ID=" + appId,
            "-DAPP_NAME=" + label,
            "-DAPP_VERSION=" + version,
            "-DAPP_BUILD=" + build,
        ]);
        Sys.println("--- heaps-ios: building (the first run downloads and compiles SDL3 and the other libraries) ---");
        run("cmake", ["--build", buildDir, "--target", "app", "-j" + cpus()]);
        var app = Path.join([buildDir, "HeapsApp.app"]);
        if (!FileSystem.exists(app)) fail('the build made no $app');
        Sys.println('--- heaps-ios: built $app ---');

        var device = bootedSimulator();
        if (device == null) {
            device = firstIPhone();
            if (device == null) fail("no iPhone simulator is installed (Xcode > Settings > Components)");
            Sys.println('--- heaps-ios: booting simulator ${device.name} ---');
            run("xcrun", ["simctl", "boot", device.udid]);
        }
        Sys.command("open", ["-a", "Simulator"]);
        Sys.println('--- heaps-ios: installing on ${device.name} and launching $appId ---');
        run("xcrun", ["simctl", "install", device.udid, app]);
        // A copy already running keeps the old binary on screen.
        Sys.command("xcrun", ["simctl", "terminate", device.udid, appId]);
        run("xcrun", ["simctl", "launch", device.udid, appId]);
    }

    /** The HashLink checkout: $HASHLINK_SRC, else the one the project's `hashlink` lib links into. */
    static function hashlinkSource():String {
        var env = Sys.getEnv("HASHLINK_SRC");
        var dir = env != null && env != "" ? env : null;
        if (dir == null) {
            var lib = output("haxelib", ["libpath", "hashlink"]);
            if (lib != null) dir = Path.normalize(Path.join([lib, "..", ".."]));
        }
        if (dir == null || !FileSystem.exists(Path.join([dir, "libs/sdl/sdl.c"])))
            fail("no HashLink source: set HASHLINK_SRC to a HashLink 2.0+ checkout, or `haxelib dev hashlink <checkout>/other/haxelib`");
        return dir;
    }

    static function simulators():Array<{name:String, udid:String, state:String}> {
        var json = output("xcrun", ["simctl", "list", "devices", "available", "-j"]);
        if (json == null) return [];
        var found = [];
        var runtimes:haxe.DynamicAccess<Array<Dynamic>> = haxe.Json.parse(json).devices;
        var names = [for (k in runtimes.keys()) k];
        names.sort(Reflect.compare);
        names.reverse();   // newest iOS first
        for (rt in names) if (rt.indexOf("iOS") >= 0)
            for (d in runtimes[rt]) found.push({name: (d.name : String), udid: (d.udid : String), state: (d.state : String)});
        return found;
    }

    static function bootedSimulator() {
        for (d in simulators()) if (d.state == "Booted") return d;
        return null;
    }

    static function firstIPhone() {
        for (d in simulators()) if (StringTools.startsWith(d.name, "iPhone")) return d;
        return null;
    }

    static function cpus():String {
        var n = output("sysctl", ["-n", "hw.ncpu"]);
        return n != null && Std.parseInt(n) != null ? n : "4";
    }

    /** A command's trimmed stdout, or null if it failed. stdout is drained before the exit code is read. */
    static function output(cmd:String, args:Array<String>):Null<String> {
        try {
            var p = new Process(cmd, args);
            var out = p.stdout.readAll().toString();
            var code = p.exitCode();
            p.close();
            return code == 0 ? StringTools.trim(out) : null;
        } catch (e:Dynamic) return null;
    }

    static function run(cmd:String, args:Array<String>) {
        var code = Sys.command(cmd, args);
        if (code != 0) fail('$cmd ${args[0]} failed ($code)');
    }

    static function fail(msg:String) {
        Sys.println('heaps-ios: $msg');
        Sys.exit(1);
    }
}
