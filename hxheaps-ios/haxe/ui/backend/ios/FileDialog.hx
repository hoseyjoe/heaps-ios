package haxe.ui.backend.ios;

/** What a dialog returned. */
enum PickResult {
    Cancelled;
    Failed(message:String);
    Picked(value:String);
}

/**
 * The iOS document picker (UIDocumentPickerViewController, the Files app's sheet): opening a file
 * and "save as". The same calls as heaps-android's haxe.ui.backend.android.FileDialog, so an app
 * branches on the define and nothing else.
 *
 * A dialog is asynchronous: the call returns at once and the callback runs once the user has
 * picked or cancelled. One dialog at a time. Off iOS every call answers a cancel immediately.
 *
 *   FileDialog.openToFile("*\/*", "imports", (path, error) -> ...);
 *   FileDialog.saveAs("application/pdf", "Report.pdf", bytes, (saved, error) -> ...);
 *
 * Natives (ios-shell/file_dialog.m), strings as zero-terminated UTF-16 hl.Bytes as in
 * heaps-android: a String argument would arrive as a pointer to the string object.
 */
class FileDialog {
    /** Where `openToFile` copies a pick by default, relative to the working directory (the app's
        Application Support folder: see main_shim.m). */
    public static inline var DEFAULT_PICK_DIR = "picked";
    public static inline var DEFAULT_ERROR = "Could not import the picked file";
    /** Where `saveAs` stages the bytes, relative to the working directory. */
    public static inline var SAVE_STAGING = "exports/pending-export";
    public static inline var DEFAULT_SAVE_ERROR = "Could not save the file";
    public static inline var BUSY = "Another file dialog is open";

    #if (heaps_ios && hl)
    @:hlNative("haxeui", "file_dialog_open")
    static function _open(mimeType:hl.Bytes, destSubdir:hl.Bytes):Void {}

    @:hlNative("haxeui", "file_dialog_pending")
    static function _pending():Bool { return false; }

    @:hlNative("haxeui", "file_dialog_result")
    static function _result():hl.Bytes { return null; }

    @:hlNative("haxeui", "file_dialog_save")
    static function _save(mimeType:hl.Bytes, suggestedName:hl.Bytes, source:hl.Bytes):Void {}

    static var _callback:Null<PickResult->Void> = null;
    static var _polling:Bool = false;

    static function start(callback:PickResult->Void, native:() -> Void):Void {
        if (_callback != null) {
            callback(Failed(BUSY));
            return;
        }
        _callback = callback;
        native();
        if (!_polling) {
            _polling = true;
            haxe.Timer.delay(_poll, 100);
        }
    }

    static function _poll():Void {
        if (_pending()) {
            haxe.Timer.delay(_poll, 100);
            return;
        }
        _polling = false;
        var cb = _callback;
        _callback = null;
        if (cb != null) {
            var raw = _result();
            cb(parseResult(raw == null ? null : @:privateAccess String.fromUCS2(raw)));
        }
    }
    #end

    /**
     * Shows the picker and copies what the user picks into `subdir` of the working directory,
     * handing back the copy's absolute path. iOS lends a picked document only for the length of
     * the callback, so there is no reading it in place later.
     *
     * @param mimeType  what can be picked ("*\/*": anything; a type iOS does not know: anything).
     * @param callback  `(path, null)` picked, `(null, message)` failed, `(null, null)` cancelled.
     */
    public static function openToFile(mimeType:String = "*/*", subdir:String = DEFAULT_PICK_DIR,
                                      callback:(path:Null<String>, error:Null<String>)->Void):Void {
        #if (heaps_ios && hl)
        start(function(result:PickResult) {
            if (callback == null) return;
            switch (result) {
                case Picked(path): callback(path, null);
                case Failed(message): callback(null, message);
                case Cancelled: callback(null, null);
            }
        }, () -> _open(@:privateAccess mimeType.bytes, @:privateAccess subdir.bytes));
        #else
        if (callback != null) callback(null, null);
        #end
    }

    /**
     * Asks the user where to save `bytes`, with `suggestedName` filled in, and writes them there.
     * The bytes are staged in the working directory (`SAVE_STAGING`); the staged file is removed
     * once the outcome is known.
     *
     * @param callback  `(true, null)` saved, `(false, message)` failed, `(false, null)` cancelled.
     */
    public static function saveAs(mimeType:String, suggestedName:String, bytes:haxe.io.Bytes,
                                  callback:(saved:Bool, error:Null<String>)->Void):Void {
        #if (heaps_ios && hl)
        if (_callback != null) {
            callback(false, BUSY);
            return;
        }
        try {
            sys.FileSystem.createDirectory(haxe.io.Path.directory(SAVE_STAGING));
            sys.io.File.saveBytes(SAVE_STAGING, bytes);
        } catch (e:haxe.Exception) {
            callback(false, "Could not prepare the file: " + e.message);
            return;
        }
        var title = suggestedTitle(suggestedName), source = SAVE_STAGING;
        start(function(result:PickResult) {
            try sys.FileSystem.deleteFile(SAVE_STAGING) catch (e:haxe.Exception) {}
            var o = saveOutcome(result);
            callback(o.saved, o.error);
        }, () -> _save(@:privateAccess mimeType.bytes, @:privateAccess title.bytes, @:privateAccess source.bytes));
        #else
        callback(false, null);
        #end
    }

    /** `name` as a file name: control characters and "/" become "_". Never empty. */
    public static function suggestedTitle(name:String):String {
        var b = new StringBuf();
        for (c in new haxe.iterators.StringIteratorUnicode(name == null ? "" : name))
            b.addChar(c < 0x20 || c == "/".code ? "_".code : c);
        var t = b.toString();
        return t.length == 0 ? "export" : t;
    }

    /** A save's result as `saveAs` reports it. */
    public static function saveOutcome(result:PickResult):{saved:Bool, error:Null<String>} return switch (result) {
        case Picked(_): {saved: true, error: null};
        case Failed(message): {saved: false, error: message == DEFAULT_ERROR ? DEFAULT_SAVE_ERROR : message};
        case Cancelled: {saved: false, error: null};
    }

    /** The native result string as a PickResult: "" is a cancel, a leading "!" a failure whose
        message follows, anything else what was picked. */
    public static function parseResult(raw:Null<String>):PickResult {
        if (raw == null || raw.length == 0) return Cancelled;
        if (raw.charAt(0) != "!") return Picked(raw);
        var message = raw.substr(1);
        return Failed(message.length > 0 ? message : DEFAULT_ERROR);
    }
}
