#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release
app="$PWD/dist/AIEventExtractor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Remove the executable left by pre-rename builds before signing the bundle.
rm -f "$app/Contents/MacOS/CreateEvent"
cp "$(swift build -c release --show-bin-path)/AIEventExtractor" "$app/Contents/MacOS/AIEventExtractor"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/de.lproj Resources/en.lproj "$app/Contents/Resources/"
# A stable local identity keeps Calendar and Keychain permissions across rebuilds; ad-hoc signing
# would make every build a new app for macOS. Neither is suitable for a notarized public release.
identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    if security find-identity -p codesigning | grep -q '"AIEventExtractor Local"'; then
        identity="AIEventExtractor Local"
    else
        identity="-"
    fi
fi
codesign --force --sign "$identity" "$app"
plutil -lint "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Resources/de.lproj/ServicesMenu.strings" "$app/Contents/Resources/en.lproj/ServicesMenu.strings"
codesign --verify --strict "$app"
print "Built: $app"
