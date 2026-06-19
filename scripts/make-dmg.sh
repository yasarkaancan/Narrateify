#!/bin/bash
#
# Builds a Release Narrateify.app and packages it into a drag-to-install DMG.
#
#   ./scripts/make-dmg.sh
#
# Output: dist/Narrateify-<version>.dmg
#
# If a "Developer ID Application" identity and a notarytool keychain profile
# (default name "narrateify") are present, the app and DMG are Developer-ID
# signed, notarized, and stapled — installing with no Gatekeeper warning.
# Otherwise it falls back to ad-hoc signing (needs a one-time Gatekeeper bypass).
set -euo pipefail

APP_NAME="Narrateify"
CONFIG="Release"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Build/stage/sign OUTSIDE the project directory. If the repo sits under
# Desktop/Documents with iCloud Drive sync on, the fileprovider continuously
# re-adds FinderInfo/provenance xattrs to the bundle, which codesign rejects as
# "detritus". A per-user temp dir is never synced, so the bundle stays clean.
BUILD_DIR="${TMPDIR:-/tmp}/narrateify-build"
DERIVED="$BUILD_DIR/DerivedData"
STAGE="$BUILD_DIR/stage"
DIST="$ROOT/dist"
rm -rf "$BUILD_DIR"

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

# Find a "Developer ID Application" identity for notarized distribution.
# Override the auto-detection with NARRATEIFY_SIGN_ID="Developer ID Application: …".
SIGN_ID="${NARRATEIFY_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)"$/\1/')"
fi

VERSION="$(/usr/bin/defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0")"
echo "==> Packaging version $VERSION"

# Stage a CLEAN copy of the app next to an /Applications symlink. `ditto` with
# these flags drops resource forks / extended attributes / ACLs, so the copy is
# free of the com.apple.macl + provenance "detritus" that makes codesign fail.
# We sign the staged copy — the exact bundle that goes into the DMG.
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto --norsrc --noextattr --noacl "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

STAGED_APP="$STAGE/$APP_NAME.app"

if [ -n "$SIGN_ID" ]; then
    echo "==> Signing with Developer ID + hardened runtime"
    echo "    $SIGN_ID"
    # codesign can be flaky if a stray xattr lands on the bundle between the
    # clear and the sign; clear + sign + verify, retrying a couple of times.
    signed=false
    for attempt in 1 2 3; do
        xattr -cr "$STAGED_APP"
        if out="$(codesign --force --options runtime --timestamp \
                      --sign "$SIGN_ID" "$STAGED_APP" 2>&1)"; then
            # Verify via a captured string, NOT `… | grep -q`: grep -q closes the
            # pipe on first match, codesign dies with SIGPIPE, and `set -o
            # pipefail` would turn that into a false "signing failed".
            info="$(codesign -dvv "$STAGED_APP" 2>&1 || true)"
            if [[ "$info" == *"Authority=Developer ID Application"* ]]; then
                signed=true
                break
            fi
            echo "    attempt $attempt: codesign ok but signature isn't Developer ID"
        else
            echo "    attempt $attempt failed: $out"
        fi
        sleep 5   # space out retries: the secure-timestamp server throttles bursts
    done
    if ! $signed; then
        echo "error: Developer ID signature did not apply after retries" >&2
        exit 1
    fi
else
    echo "==> No Developer ID found — ad-hoc signing (DMG will need a Gatekeeper bypass)"
    xattr -cr "$STAGED_APP"
    codesign --force --deep --sign - "$STAGED_APP"
fi
codesign --verify --strict "$STAGED_APP"
echo "    signature OK"

mkdir -p "$DIST"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

# Notarize + staple when we have a Developer ID and stored notary credentials.
# Set up the profile once with:
#   xcrun notarytool store-credentials "$NARRATEIFY_NOTARY_PROFILE" …
NOTARY_PROFILE="${NARRATEIFY_NOTARY_PROFILE:-narrateify}"
NOTARIZE=false
if [ -n "$SIGN_ID" ] && \
   xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    NOTARIZE=true
fi

if $NOTARIZE; then
    # Notarize the app first and staple the ticket INTO the bundle, so it passes
    # Gatekeeper even offline once a user drags it out of the DMG.
    echo "==> Notarizing the app (profile: $NOTARY_PROFILE)…"
    APP_ZIP="$BUILD_DIR/$APP_NAME.zip"
    ditto -c -k --keepParent "$STAGED_APP" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling ticket to the app"
    xcrun stapler staple "$STAGED_APP"
    xcrun stapler validate "$STAGED_APP"
fi

echo "==> Creating $DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

if $NOTARIZE; then
    # Sign the DMG too, then notarize + staple it, so the download itself has a
    # usable Developer ID signature (not just the app inside).
    echo "==> Signing the DMG"
    codesign --force --sign "$SIGN_ID" "$DMG"
    echo "==> Notarizing the DMG…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG" && echo "    DMG staple OK"
    echo "==> Gatekeeper assessment:"
    spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | head -3 || true
else
    echo "==> Skipping notarization (need a Developer ID + 'notarytool store-credentials $NOTARY_PROFILE')"
fi

# Tidy the heavy build tree; keep only the DMG.
rm -rf "$BUILD_DIR"

echo "==> Done: $DMG"
ls -lh "$DMG" | awk '{print $5, $9}'
