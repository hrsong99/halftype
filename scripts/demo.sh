#!/bin/zsh
# Makes the README's pictures: docs/media/demo.gif from the real model, and the window's pages (on screen only behind the desktop, as
# Metal draws the sky only there). Shows nothing and takes no keys.
# Usage: scripts/demo.sh <gguf>
set -euo pipefail
cd "${0:A:h}/.."
args=(-c release -Xswiftc -enable-testing --disable-keychain --scratch-path .build/e2e --product halftype-e2e)
swift build "${args[@]}" >/dev/null  # Or a failed build would make the pictures from the last one.
bin="$(swift build "${args[@]}" --show-bin-path)/halftype-e2e"
frames=$(mktemp -d); media=$PWD/docs/media; mkdir -p "$media"
# Invented, and chosen as ones the default model does well on, which the README says. English only for now.
sentences=("Thanks so much for your help! Please let me know if you have any other questions."
           "Happy birthday! I hope you have a wonderful day with your family and friends.")
"$bin" --demo "$1" "$frames" "${sentences[@]}"
"$bin" --window-shots "$media"
cd "$frames"
in=(); while read -r file delay; do in+=(-delay "$delay" "$file"); done < en-delays.txt
magick -loop 0 "${in[@]}" -resize 760x +dither -colors 64 +remap -layers Optimize "$media/demo.gif" < /dev/null
ls -la "$media"
