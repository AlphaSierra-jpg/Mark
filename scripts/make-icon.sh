#!/usr/bin/env bash
#
# Turns one square source image into Mark's app icon.
#
#   ./scripts/make-icon.sh ~/Downloads/mark-logo.png
#
# Feed it the largest version you have — 1024x1024 is what the icon guidelines
# ask for. Every macOS size is derived from it and written into the asset
# catalog, so the next build picks the icon up with no further steps.
#
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="${1:-}"
ICONSET="Mark/Assets.xcassets/AppIcon.appiconset"

if [[ -z "$SOURCE" ]]; then
    echo "usage: $0 <source.png>" >&2
    exit 1
fi

[[ -f "$SOURCE" ]] || { echo "error: no such file: $SOURCE" >&2; exit 1; }

WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/{print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/{print $2}')

[[ "$WIDTH" == "$HEIGHT" ]] || {
    echo "error: icon must be square, got ${WIDTH}x${HEIGHT}" >&2
    exit 1
}

if (( WIDTH < 1024 )); then
    echo "warning: source is ${WIDTH}px; 1024px gives a sharper result on Retina" >&2
fi

echo "==> Slicing ${SOURCE} (${WIDTH}px)"
rm -f "${ICONSET}"/*.png

# point size, scale -> rendered pixels
for entry in "16 1" "16 2" "32 1" "32 2" "128 1" "128 2" "256 1" "256 2" "512 1" "512 2"; do
    read -r POINTS SCALE <<< "$entry"
    PIXELS=$(( POINTS * SCALE ))
    SUFFIX=""
    (( SCALE == 2 )) && SUFFIX="@2x"
    NAME="icon_${POINTS}x${POINTS}${SUFFIX}.png"
    sips -s format png -z "$PIXELS" "$PIXELS" "$SOURCE" --out "${ICONSET}/${NAME}" > /dev/null
    echo "    ${NAME}  (${PIXELS}px)"
done

echo "==> Updating Contents.json"
python3 - "$ICONSET" <<'PY'
import json, sys, pathlib

iconset = pathlib.Path(sys.argv[1])
sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
         (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

images = []
for points, scale in sizes:
    suffix = "@2x" if scale == 2 else ""
    images.append({
        "filename": f"icon_{points}x{points}{suffix}.png",
        "idiom": "mac",
        "scale": f"{scale}x",
        "size": f"{points}x{points}",
    })

doc = {"images": images, "info": {"author": "xcode", "version": 1}}
(iconset / "Contents.json").write_text(json.dumps(doc, indent=2) + "\n")
PY

echo
echo "Done. Rebuild to see it:"
echo "    ./scripts/make-dmg.sh"
