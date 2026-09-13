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
# Ad-hoc signing is suitable for local builds, not a notarized public release.
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$app"
plutil -lint "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Resources/de.lproj/ServicesMenu.strings" "$app/Contents/Resources/en.lproj/ServicesMenu.strings"
codesign --verify --strict "$app"
print "Built: $app"
