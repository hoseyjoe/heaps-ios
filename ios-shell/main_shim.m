// The app's entry point. SDL_main.h renames the `main` below to SDL_main and supplies the real
// one, which starts UIKit and calls it back on the main thread once the app is up. HashLink's own
// main (hlc_main.c, included by the generated main.c) is compiled as heaps_ios_hl_main: see
// CMakeLists.txt.
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <unistd.h>

extern int heaps_ios_hl_main(int argc, char *argv[]);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // The bundle cannot be written to on a device, and an update replaces it. What the app
        // keeps (settings, a database "next to the app") goes in Application Support, which iOS
        // backs up and hides from the Files app: that is HOME and the working directory.
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *data = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        if (data && [fm createDirectoryAtPath:data withIntermediateDirectories:YES attributes:nil error:nil]) {
            setenv("HOME", [data fileSystemRepresentation], 1);
            chdir([data fileSystemRepresentation]);
            // Heaps opens the project's assets/ folder relative to the working directory: a link
            // to the one in the bundle, remade every launch since the bundle moves with an update.
            NSString *link = [data stringByAppendingPathComponent:@"assets"];
            NSString *assets = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"assets"];
            [fm removeItemAtPath:link error:nil];
            [fm createSymbolicLinkAtPath:link withDestinationPath:assets error:nil];
        }
    }
    // SDL raises the on-screen keyboard with text input only when it sees no hardware keyboard,
    // and in the Simulator it always sees the Mac's. Always ask: iOS itself keeps the keyboard
    // down while a real one is attached.
    SDL_SetHint(SDL_HINT_ENABLE_SCREEN_KEYBOARD, "1");
    return heaps_ios_hl_main(argc, argv);
}
