#!/bin/sh
# Build Resources/AppIcon.icns and assets/brand/icon.png from the generated artwork in assets/brand/icon-source.png.
# The source is a GPT Image 2 render (1254x1254) whose tile sits at TILE; we cut it out, mask it to the
# macOS icon shape (824px tile, 100px margins on a 1024 canvas) and add the standard soft shadow.
#   TILE  crop geometry of the tile inside the source, default 977x956+138+140
set -eu
cd "$(dirname "$0")/.."
TILE="${TILE:-977x956+138+140}"
SRC=assets/brand/icon-source.png
OUT=assets/brand/icon.png
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

magick "$SRC" -crop "$TILE" +repage -resize '824x824!' -alpha set \
  \( -size 824x824 xc:none -fill white -draw 'roundrectangle 0,0 823,823 185,185' \) \
  -compose DstIn -composite "$T/tile.png"
magick -size 1024x1024 xc:none \
  \( "$T/tile.png" -background black -shadow 35x12+0+10 \) -geometry +88+92 -composite \
  "$T/tile.png" -geometry +100+100 -composite "$OUT"

mkdir "$T/AppIcon.iconset"
for s in 16 32 128 256 512; do
  magick "$OUT" -resize ${s}x${s} "$T/AppIcon.iconset/icon_${s}x${s}.png"
  magick "$OUT" -resize $((s * 2))x$((s * 2)) "$T/AppIcon.iconset/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$T/AppIcon.iconset" -o Resources/AppIcon.icns
echo "built $OUT and Resources/AppIcon.icns"
