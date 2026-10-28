#!/usr/bin/env bash
#
# Builds Mark and packages it as a DMG ready to attach to a GitHub release.
#
# Uses nothing but Xcode and the tools that ship with macOS, so it runs the
# same on a clean machine as it does here.
#
#   ./scripts/make-dmg.sh            # build, then package
#   ./scripts/make-dmg.sh --no-build # package whatever is already built
#
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="Release"
DERIVED_DATA="build"
DIST="dist"
APP_NAME="Mark"

SKIP_BUILD=0
[[ "${1:-}" == "--no-build" ]] && SKIP_BUILD=1

APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo "==> Generating Xcode project"
    xcodegen generate

    echo "==> Building ${CONFIGURATION}"
    xcodebuild \
        -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -configuration "${CONFIGURATION}" \
        -derivedDataPath "${DERIVED_DATA}" \
        CODE_SIGN_IDENTITY="-" \
        build
fi

[[ -d "$APP" ]] || { echo "error: ${APP} not found — run without --no-build" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Contents/Info.plist")
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"

# The staging folder is exactly what the mounted volume shows: the app, and a
# shortcut to drag it onto.
echo "==> Staging"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

echo "==> Creating ${DMG}"
mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    "$DMG"

# Ad hoc signing the image too, so Gatekeeper reports a consistent story for
# the download and the app inside it.
codesign --force --sign - "$DMG"

echo
echo "${DMG}  ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
