#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${DOCKNOTES_BUILD_CONFIGURATION:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "DOCKNOTES_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
fi
app_dir="$project_dir/build/DockNotes.app"
staging_root="$(mktemp -d "$project_dir/build/.docknotes-stage.XXXXXX")"
staging_app="$staging_root/DockNotes.app"
contents_dir="$staging_app/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
previous_app="$project_dir/build/.DockNotes.previous"
legacy_previous_app="$project_dir/build/.DockNotes.previous.app"
trap 'rm -rf "$staging_root"' EXIT

export SWIFTPM_MODULECACHE_OVERRIDE="/private/tmp/docknotes-swift-cache"
export CLANG_MODULE_CACHE_PATH="/private/tmp/docknotes-clang-cache"
sdk_26_5="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -d "$sdk_26_5" ]]; then
    # Build against the newest installed SDK so availability-guarded Liquid
    # Glass APIs compile, while Package.swift keeps the deployment target at
    # macOS 15 for the material fallback.
    export SDKROOT="$sdk_26_5"
else
    export SDKROOT="$(xcrun --show-sdk-path)"
fi

mkdir -p "$SWIFTPM_MODULECACHE_OVERRIDE" "$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox -c "$configuration" --package-path "$project_dir"

mkdir -p "$macos_dir" "$resources_dir"
install -m 755 "$project_dir/.build/$configuration/DockNotes" "$macos_dir/DockNotes"
install -m 644 "$project_dir/AppResources/Info.plist" "$contents_dir/Info.plist"
build_number="$(date '+%Y%m%d%H%M%S')"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_dir/Info.plist"
install -m 644 "$project_dir/Sources/DockNotesApp/Resources/paper-texture.png" "$resources_dir/paper-texture.png"
install -m 644 "$project_dir/Sources/DockNotesApp/Resources/app-icon.png" "$resources_dir/app-icon.png"
install -m 644 "$project_dir/Sources/DockNotesApp/Resources/tray-icon.png" "$resources_dir/tray-icon.png"
# Release builders can provide a trusted signing identity. Local builds remain
# ad-hoc signed without weakening the Keychain boundary to an identifier-only
# designated requirement.
if [[ -n "${DOCKNOTES_CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
        --sign "$DOCKNOTES_CODESIGN_IDENTITY" \
        "$staging_app"
else
    codesign --force --sign - "$staging_app"
fi

# Reusing the existing bundle directory preserves Finder's creation date and
# makes it easy to reopen a stale process. Install a freshly-created bundle and
# retain the immediately previous build as a rollback copy.
rm -rf "$previous_app" "$legacy_previous_app"
if [[ -d "$app_dir" ]]; then
    mv "$app_dir" "$previous_app"
fi
mv "$staging_app" "$app_dir"

echo "$app_dir"
