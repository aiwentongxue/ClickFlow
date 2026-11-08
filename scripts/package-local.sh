#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=1.0.3
output="$PWD/dist/$version"
mkdir -p "$output"
xcodebuild -project ClickFlow.xcodeproj -scheme ClickFlow -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/ReleaseData build
app=build/ReleaseData/Build/Products/Release/ClickFlow.app
architectures=$(/usr/bin/lipo -archs "$app/Contents/MacOS/ClickFlow")
[[ "$architectures" == "arm64 x86_64" || "$architectures" == "x86_64 arm64" ]]
stage=$(mktemp -d "${TMPDIR%/}/ClickFlow-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
# Keep the package source outside synced Documents folders, which can acquire
# Finder metadata immediately after clearing extended attributes.
/usr/bin/ditto --norsrc --noextattr "$app" "$stage/ClickFlow.app"
/usr/bin/xattr -cr "$stage/ClickFlow.app"
/usr/bin/codesign --verify --deep --strict "$stage/ClickFlow.app"
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$stage/ClickFlow.app" "$output/ClickFlow-$version-app.zip"
ln -s /Applications "$stage/Applications"
/usr/bin/hdiutil create -ov -format UDZO -volname "ClickFlow $version" \
  -srcfolder "$stage" "$output/ClickFlow-$version.dmg"
echo "Packaged app: $output"
