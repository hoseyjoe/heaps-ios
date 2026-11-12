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
        // What the app keeps (settings, its database) is resolved from HOME: the container's
        // root is not writable on a device, its Documents folder is.
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (docs) setenv("HOME", [docs fileSystemRepresentation], 1);
        // The project's assets/ folder is in the bundle; Heaps opens it relative to here.
        NSString *res = [[NSBundle mainBundle] resourcePath];
        if (res) chdir([res fileSystemRepresentation]);
    }
    return heaps_ios_hl_main(argc, argv);
}
