#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/build/DockNotes.app"
staging_root="$(mktemp -d "$project_dir/build/.docknotes-stage.XXXXXX")"
staging_app="$staging_root/DockNotes.app"
contents_dir="$staging_app/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
previous_app="$project_dir/build/.DockNotes.previous.app"
trap 'rm -rf "$staging_root"' EXIT

export SWIFTPM_MODULECACHE_OVERRIDE="/private/tmp/docknotes-swift-cache"
export CLANG_MODULE_CACHE_PATH="/private/tmp/docknotes-clang-cache"
sdk_15_2="/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk"
if [[ -d "$sdk_15_2" ]]; then
    export SDKROOT="$sdk_15_2"
else
    export SDKROOT="$(xcrun --show-sdk-path)"
fi

mkdir -p "$SWIFTPM_MODULECACHE_OVERRIDE" "$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -c debug --package-path "$project_dir"

mkdir -p "$macos_dir" "$resources_dir"
install -m 755 "$project_dir/.build/debug/DockNotes" "$macos_dir/DockNotes"
install -m 644 "$project_dir/AppResources/Info.plist" "$contents_dir/Info.plist"
build_number="$(date '+%Y%m%d%H%M%S')"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_dir/Info.plist"
install -m 644 "$project_dir/Sources/DockNotesApp/Resources/paper-texture.png" "$resources_dir/paper-texture.png"
install -m 644 "$project_dir/Sources/DockNotesApp/Resources/app-icon.png" "$resources_dir/app-icon.png"
install -m 644 "$project_dir/Sources/DockNotesApp/Resources/tray-icon.png" "$resources_dir/tray-icon.png"
codesign --force --sign - "$staging_app"

# Reusing the existing bundle directory preserves Finder's creation date and
# makes it easy to reopen a stale process. Install a freshly-created bundle and
# retain the immediately previous build as a rollback copy.
rm -rf "$previous_app"
if [[ -d "$app_dir" ]]; then
    mv "$app_dir" "$previous_app"
fi
mv "$staging_app" "$app_dir"

echo "$app_dir"
