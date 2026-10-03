#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ "${1:-}" != "--skip-build" ]]; then
  ./tools/flutterw build macos --release
fi

app_bundle="build/macos/Build/Products/Release/Moonveil.app"
release_archive="output/releases/moonveil-macos.zip"

# Incremental Xcode builds may keep the host seal while Flutter replaces its
# App.framework. Seal the finished local bundle and preserve sandbox entitlements.
codesign --force --sign - "$app_bundle/Contents/Frameworks/App.framework"
codesign --force --sign - --preserve-metadata=entitlements "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
mkdir -p output/releases
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$release_archive"
echo "Saved $release_archive"
