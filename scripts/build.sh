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

# The icon is drawn by scripts/make-icon.swift and converted into all sizes macOS asks for.
iconset="$PWD/.build/AppIcon.iconset"
mkdir -p "$iconset"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.png" >/dev/null
for size in 16 32 128 256 512; do
    sips -z $size $size "$PWD/.build/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$PWD/.build/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
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
