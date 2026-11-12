#!/bin/sh
# add_icon.sh <icon.png> <work dir> <app bundle> <SDK name or path> <minimum iOS>
# Compiles a 1024 px PNG into the bundle as its app icon. An asset catalog with the one image is
# built in <work dir> and compiled by actool, which makes every size the home screen, Settings and
# Spotlight ask for (Assets.car, plus loose PNGs for the oldest callers) and says which Info.plist
# keys name them; those are merged into the bundle's Info.plist. CMakeLists.txt runs this after
# each link.
set -eu
icon=$1 work=$2 app=$3 min=$5
# CMake hands over the SDK as it resolved it: a name or the SDK's path.
case $4 in *[Ss]imulator*) platform=iphonesimulator ;; *) platform=iphoneos ;; esac

set_dir=$work/Assets.xcassets/AppIcon.appiconset
rm -rf "$work/Assets.xcassets"
mkdir -p "$set_dir"
cp "$icon" "$set_dir/AppIcon.png"
cat > "$work/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > "$set_dir/Contents.json" <<'JSON'
{
  "images" : [ { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

partial=$work/icon-partial.plist
xcrun actool "$work/Assets.xcassets" --compile "$app" --platform "$platform" \
    --minimum-deployment-target "$min" --target-device iphone --target-device ipad \
    --app-icon AppIcon --output-partial-info-plist "$partial" \
    --output-format human-readable-text --errors --warnings > "$work/actool.log" 2>&1 \
    || { cat "$work/actool.log" >&2; exit 1; }

plist=$app/Info.plist
# A second build finds the keys already there: Merge skips what exists, so drop them first.
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons~ipad" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Merge $partial" "$plist" >/dev/null
