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

# Window content size in points. Finder displays a folder's background
# picture at native pixel size (it does NOT halve it for Retina on its own),
# so we ship both background.png (1x, these exact dimensions) and
# background@2x.png (2x) — the standard HiDPI pair Finder/NSImage resolve
# automatically, same as everywhere else on macOS.
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128

# Measured from the source background's two inset wells (see
# scripts/dmg-background-positions.md if that ever needs re-deriving): each
# well's centre, as a fraction of the image's own width/height.
APP_X_FRACTION=0.285
APPLICATIONS_X_FRACTION=0.715
WELL_Y_FRACTION=0.5

# Finder's "position of item" places the centre of the icon+label block, not
# the icon glyph alone — the label pulls it down, and label text width pulls
# it sideways. Measured empirically (screenshot the result, compare icon
# centre to well centre) at icon size 128; re-measure if ICON_SIZE changes.
POSITION_X_CORRECTION=-8
POSITION_Y_CORRECTION=-17

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
VOLUME_NAME="${APP_NAME} ${VERSION}"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
RW_DMG="${DIST}/.${APP_NAME}-${VERSION}-rw.dmg"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"

STAGE=$(mktemp -d)
MOUNT_POINT=""
cleanup() {
    [[ -n "$MOUNT_POINT" ]] && hdiutil detach "$MOUNT_POINT" -quiet -force 2>/dev/null || true
    rm -rf "$STAGE"
}
trap cleanup EXIT

echo "==> Staging"
ditto "$APP" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

BACKGROUND_SOURCE="dmg_background.png"
if [[ -f "$BACKGROUND_SOURCE" ]]; then
    echo "==> Preparing background"
    mkdir -p "${STAGE}/.background"
    sips -s format png \
        -z "$WINDOW_HEIGHT" "$WINDOW_WIDTH" \
        "$BACKGROUND_SOURCE" \
        --out "${STAGE}/.background/background.png" > /dev/null
    sips -s format png \
        -z $((WINDOW_HEIGHT * 2)) $((WINDOW_WIDTH * 2)) \
        "$BACKGROUND_SOURCE" \
        --out "${STAGE}/.background/background@2x.png" > /dev/null
fi

mkdir -p "$DIST"
rm -f "$DMG" "$RW_DMG"

echo "==> Creating writable image"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDRW \
    -quiet \
    "$RW_DMG"

MOUNT_POINT="/Volumes/${VOLUME_NAME}"
hdiutil attach "$RW_DMG" -quiet -mountpoint "$MOUNT_POINT"

if [[ -f "$BACKGROUND_SOURCE" ]]; then
    echo "==> Arranging icons"
    APP_X=$(python3 -c "print(round(${APP_X_FRACTION} * ${WINDOW_WIDTH}) + ${POSITION_X_CORRECTION})")
    APPLICATIONS_X=$(python3 -c "print(round(${APPLICATIONS_X_FRACTION} * ${WINDOW_WIDTH}) + ${POSITION_X_CORRECTION})")
    WELL_Y=$(python3 -c "print(round(${WELL_Y_FRACTION} * ${WINDOW_HEIGHT}) + ${POSITION_Y_CORRECTION})")
    WINDOW_RIGHT=$((100 + WINDOW_WIDTH))
    # TITLE_BAR_HEIGHT accounts for the title bar, which "window bounds"
    # includes but the icon view content area (and so the background image)
    # does not. Calibrated empirically: too large and Finder tiles a second
    # copy of the background below the first.
    TITLE_BAR_HEIGHT=20
    WINDOW_BOTTOM=$((100 + WINDOW_HEIGHT + TITLE_BAR_HEIGHT))

    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, ${WINDOW_RIGHT}, ${WINDOW_BOTTOM}}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to ${ICON_SIZE}
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {${APP_X}, ${WELL_Y}}
        set position of item "Applications" of container window to {${APPLICATIONS_X}, ${WELL_Y}}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT
fi

echo "==> Finalising"
# Finder writes its metadata asynchronously; give it a moment before unmounting.
sync
sleep 1
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -f "$RW_DMG"

# Ad hoc signing the image too, so Gatekeeper reports a consistent story for
# the download and the app inside it.
codesign --force --sign - "$DMG"

echo
echo "${DMG}  ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
