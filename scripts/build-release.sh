#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) Release build of tat and packages it as .zip and .dmg in dist/.
# Usage: scripts/build-release.sh <version> [build-number]
set -euo pipefail

VERSION="${1:?usage: scripts/build-release.sh <version> [build-number]}"
BUILD_NUMBER="${2:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d Tat.xcodeproj ]; then
  xcodegen generate
fi

rm -rf build/release build/dmg dist
xcodebuild \
  -project Tat.xcodeproj \
  -scheme Tat \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/release \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

APP="build/release/Build/Products/Release/tat.app"
# Ad-hoc signature: no Apple Developer account needed. Users clear quarantine once (see README).
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

mkdir -p dist
ditto -c -k --keepParent "$APP" "dist/tat-$VERSION.zip"

mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "tat $VERSION" -srcfolder build/dmg -ov -format UDZO "dist/tat-$VERSION.dmg" >/dev/null

(cd dist && shasum -a 256 tat-* > SHA256SUMS.txt)
echo "Built tat $VERSION ($BUILD_NUMBER):"
ls -lh dist
