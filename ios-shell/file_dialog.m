// The natives behind haxe.ui.backend.ios.FileDialog: the iOS document picker for opening a file
// and for "save as". Called from HashLink C as haxeui_file_dialog_*; strings are zero-terminated
// UTF-16 (hl.Bytes), as in heaps-android's shim.
//
// SDL runs the app's main on the UIKit main thread, so these are on it already, and the picker's
// delegate is called from inside SDL's event pump. The result waits in one slot until Haxe, which
// polls haxeui_file_dialog_pending, fetches it: "" is a cancel, "!message" a failure, anything
// else the path.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <SDL3/SDL.h>
#include <hl.h>
#include <stdbool.h>

static NSString *g_result = @"";
static int g_state = 0;   // 0 idle, 1 pending, 2 done

static void finish(NSString *result) {
    g_result = result ? result : @"";
    g_state = 2;
}

static NSString *from_hl(vbyte *text) {
    if (!text) return @"";
    const unichar *s = (const unichar *)text;
    NSUInteger len = 0;
    while (s[len]) len++;
    return [NSString stringWithCharacters:s length:len];
}

static vbyte *to_hl(NSString *s) {
    NSUInteger len = s.length;
    unichar *buf = (unichar *)hl_alloc_bytes((int)((len + 1) * sizeof(unichar)));
    [s getCharacters:buf range:NSMakeRange(0, len)];
    buf[len] = 0;
    return (vbyte *)buf;
}

// The view controller on top of the app's window, to present from.
static UIViewController *top_controller(void) {
    UIViewController *vc = nil;
    int count = 0;
    SDL_Window **windows = SDL_GetWindows(&count);
    if (windows) {
        if (count > 0) {
            UIWindow *w = (__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(windows[0]), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
            vc = w.rootViewController;
        }
        SDL_free(windows);
    }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

@interface HeapsIOSFileDialog : NSObject <UIDocumentPickerDelegate>
// Opening: where to copy the pick, relative to the working directory; "" hands back the pick's own path.
@property (nonatomic, copy) NSString *destSubdir;
@property (nonatomic) BOOL saving;
// Saving: the named copy of the staged bytes the picker exports, removed once it is done.
@property (nonatomic, copy) NSURL *exportCopy;
@end

@implementation HeapsIOSFileDialog

- (void)cleanUp {
    if (self.exportCopy) [[NSFileManager defaultManager] removeItemAtURL:self.exportCopy error:nil];
    self.exportCopy = nil;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) { [self cleanUp]; finish(@""); return; }
    if (self.saving) { [self cleanUp]; finish(url.path); return; }
    if (self.destSubdir.length == 0) { finish(url.path); return; }

    // The pick is a copy in the app's temporary folder (asCopy:YES): move it where Haxe asked.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [[fm currentDirectoryPath] stringByAppendingPathComponent:self.destSubdir];
    NSString *dest = [dir stringByAppendingPathComponent:url.lastPathComponent];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
        finish([@"!" stringByAppendingString:error.localizedDescription ?: @""]);
        return;
    }
    [fm removeItemAtPath:dest error:nil];
    if (![fm moveItemAtPath:url.path toPath:dest error:&error] && ![fm copyItemAtPath:url.path toPath:dest error:&error]) {
        finish([@"!" stringByAppendingString:error.localizedDescription ?: @""]);
        return;
    }
    finish(dest);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self cleanUp];
    finish(@"");
}

@end

static HeapsIOSFileDialog *g_dialog = nil;

static bool present(UIDocumentPickerViewController *picker) {
    UIViewController *vc = top_controller();
    if (!vc) return false;
    picker.delegate = g_dialog;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [vc presentViewController:picker animated:YES completion:nil];
    return true;
}

// @:hlNative("haxeui", "file_dialog_open"). mime: "*/*" or a type iOS does not know shows every
// file. dest: a folder relative to the working directory to copy the pick into, or "".
void haxeui_file_dialog_open(vbyte *mime_utf16, vbyte *dest_utf16) {
    @autoreleasepool {
        g_state = 1;
        g_result = @"";
        if (!g_dialog) g_dialog = [HeapsIOSFileDialog new];
        g_dialog.saving = NO;
        g_dialog.destSubdir = from_hl(dest_utf16);
        g_dialog.exportCopy = nil;
        NSString *mime = from_hl(mime_utf16);
        UTType *type = [mime isEqualToString:@"*/*"] ? nil : [UTType typeWithMIMEType:mime];
        if (!type) type = UTTypeItem;
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[type] asCopy:YES];
        picker.allowsMultipleSelection = NO;
        if (!present(picker)) finish(@"!file picker unavailable");
    }
}

// @:hlNative("haxeui", "file_dialog_save"). source: the staged bytes, relative to the working
// directory. The picker exports a file under its own name, so the bytes are first copied to a
// temporary file called name.
void haxeui_file_dialog_save(vbyte *mime_utf16, vbyte *name_utf16, vbyte *source_utf16) {
    @autoreleasepool {
        g_state = 1;
        g_result = @"";
        if (!g_dialog) g_dialog = [HeapsIOSFileDialog new];
        g_dialog.saving = YES;
        g_dialog.destSubdir = @"";
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *source = [[fm currentDirectoryPath] stringByAppendingPathComponent:from_hl(source_utf16)];
        NSString *name = from_hl(name_utf16).lastPathComponent;
        if (name.length == 0) name = @"export";
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"heaps-ios-export"];
        NSString *copy = [folder stringByAppendingPathComponent:name];
        NSError *error = nil;
        [fm removeItemAtPath:folder error:nil];
        if (![fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]
            || ![fm copyItemAtPath:source toPath:copy error:&error]) {
            finish([@"!" stringByAppendingString:error.localizedDescription ?: @""]);
            return;
        }
        g_dialog.exportCopy = [NSURL fileURLWithPath:copy];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[g_dialog.exportCopy] asCopy:YES];
        if (!present(picker)) { [g_dialog cleanUp]; finish(@"!file saver unavailable"); }
    }
}

// @:hlNative("haxeui", "file_dialog_pending")
bool haxeui_file_dialog_pending(void) {
    return g_state == 1;
}

// @:hlNative("haxeui", "file_dialog_result"): the result, and the slot back to idle.
vbyte *haxeui_file_dialog_result(void) {
    @autoreleasepool {
        vbyte *result = to_hl(g_result ?: @"");
        g_result = @"";
        g_state = 0;
        return result;
    }
}
