#!/bin/zsh
set -eu
cd "${0:A:h:h}"
[[ -d 'dist/Create Event.app' ]] || ./scripts/build.sh
install_root="${1:-$HOME/Applications}"
app="$install_root/Create Event.app"
mkdir -p "$install_root"
if [[ -e "$app" ]]; then
    print -u2 "An app already exists at $app. Quit it and move it aside before installing this build."
    exit 1
fi
cp -R 'dist/Create Event.app' "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
print "Installed: $app"
print 'Open it once, then reopen the source app if the Services menu is stale.'
