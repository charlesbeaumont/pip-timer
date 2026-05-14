#!/usr/bin/env bash
# Build a Release configuration of Pip and zip the .app bundle for GitHub Releases.
#
# Usage: scripts/release.sh 1.0.0
#
# Output: dist/Pip-v<VERSION>.zip
#
# Upload to a GitHub Release with:
#   gh release create v<VERSION> dist/Pip-v<VERSION>.zip --title "Pip v<VERSION>"

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 1.0.0" >&2
  exit 1
fi

VERSION="$1"

command -v xcodegen >/dev/null || { echo "xcodegen not found. brew install xcodegen" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild not found. Install Xcode." >&2; exit 1; }

cd "$(dirname "$0")/.."

rm -rf build dist
mkdir -p dist

xcodegen generate

xcodebuild \
  -project Pip.xcodeproj \
  -scheme Pip \
  -configuration Release \
  -derivedDataPath build \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  clean build

APP_PATH="build/Build/Products/Release/Pip.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but $APP_PATH not found" >&2
  exit 1
fi

ZIP_PATH="dist/Pip-v${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo
echo "Built: $ZIP_PATH"
echo
echo "Next:"
echo "  gh release create v${VERSION} ${ZIP_PATH} --title \"Pip v${VERSION}\""
