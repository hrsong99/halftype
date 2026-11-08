#!/bin/zsh
# Builds Resources/AppIcon.icns and the template menu-bar glyph from the chosen option. Run: docs/icon/build.sh [a|b|c|d]
set -euo pipefail
here=${0:A:h}; res=$here/../../Resources; pick=${1:-d}
tmp=$(mktemp -d); mkdir -p "$res"
# 1024 canvas, 824 rounded square, 100 margin: the macOS icon grid.
for id in a b c d; do
  magick "$here/option-$id-raw.png" -resize 824x824! -alpha set \
    \( -size 824x824 xc:none -fill white -draw "roundrectangle 0,0 823,823 185,185" \) -compose DstIn -composite -compose Over \
    -background none -gravity center -extent 1024x1024 PNG32:"$tmp/$id.png"
  magick "$tmp/$id.png" -resize 512x512 PNG32:"$here/option-$id.png"
done
set=$tmp/AppIcon.iconset; mkdir "$set"
for s in 16 32 128 256 512; do
  magick "$tmp/$pick.png" -filter Lanczos -resize ${s}x$s PNG32:"$set/icon_${s}x$s.png"
  magick "$tmp/$pick.png" -filter Lanczos -resize $((s*2))x$((s*2)) PNG32:"$set/icon_${s}x$s@2x.png"
done
iconutil -c icns "$set" -o "$res/AppIcon.icns"
# Template images: black plus alpha only. The system tints them for the menu bar.
rsvg-convert -w 18 -h 18 "$here/menubar.svg" -o "$res/MenuBarTemplate.png"
rsvg-convert -w 36 -h 36 "$here/menubar.svg" -o "$res/MenuBarTemplate@2x.png"
