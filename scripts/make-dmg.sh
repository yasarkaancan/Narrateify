#!/bin/bash
#
# Builds a Release Narrateify.app and packages it into a drag-to-install DMG.
#
#   ./scripts/make-dmg.sh
#
# Output: dist/Narrateify-<version>.dmg
#
# The app is ad-hoc signed (no paid Apple Developer ID), so the first launch
# on another Mac needs a one-time Gatekeeper bypass — see the README.
set -euo pipefail

APP_NAME="Narrateify"
CONFIG="Release"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/.build-dmg"
DERIVED="$BUILD_DIR/DerivedData"
STAGE="$BUILD_DIR/stage"
DIST="$ROOT/dist"

# Strip extended attributes (com.apple.macl / provenance / quarantine) from the
# inputs — Release codesigning rejects this "detritus" if it reaches the bundle.
echo "==> Clearing extended attributes from inputs"
xattr -cr "$ROOT/Sources" "$ROOT/Info.plist" 2>/dev/null || true

echo "==> Generating Xcode project from project.yml"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi
xcodegen generate

# Build without code signing — macOS keeps re-applying provenance/macl xattrs
# during the build, which the in-build codesign step rejects as "detritus".
# We strip the finished bundle and ad-hoc sign it ourselves below instead.
echo "==> Building $APP_NAME ($CONFIG)"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    build | tail -3

APP_PATH="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: built app not found at $APP_PATH" >&2
    exit 1
fi

echo "==> Stripping detritus and ad-hoc signing"
xattr -cr "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH" && echo "    signature OK"

VERSION="$(/usr/bin/defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0")"
echo "==> Packaging version $VERSION"

# Stage the .app next to an /Applications symlink so the DMG window offers a
# simple drag-to-install.
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

echo "==> Creating $DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

# Tidy the heavy build tree; keep only the DMG.
rm -rf "$BUILD_DIR"

echo "==> Done: $DMG"
ls -lh "$DMG" | awk '{print $5, $9}'
