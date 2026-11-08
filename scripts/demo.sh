#!/bin/zsh
# Makes the README's pictures: docs/media/demo.webp, a scripted illustration, and the window's pages (on screen only behind the desktop, which
# Metal needs). Shows nothing and takes no keys.
# Usage: scripts/demo.sh <gguf>
set -euo pipefail
cd "${0:A:h}/.."
args=(-c release -Xswiftc -enable-testing --disable-keychain --scratch-path .build/e2e --product halftype-e2e)
swift build "${args[@]}" >/dev/null  # Or a failed build would make the pictures from the last one.
bin="$(swift build "${args[@]}" --show-bin-path)/halftype-e2e"
frames=$(mktemp -d); media=$PWD/docs/media; mkdir -p "$media"
# An illustration, scripted, in three messages (docs/design/readme-demo round 4, B): Tab takes a short suggestion a word at a time,
# Shift-Tab a long one whole, and a wrong one is typed over. The README says so.
export HALFTYPE_DEMO_SCRIPT="$(cat docs/design/readme-demo/round4/B-script.txt)"
"$bin" --demo "$1" "$frames" "Happy birthday! I hope you have a great day!" "Thanks for the update. I'll take a look and get back to you." \
  "Running 10 minutes late, sorry! Save me a seat."
"$bin" --window-shots "$media"
cd "$frames"
in=(); while read -r file delay; do in+=(-delay "$delay" "$file"); done < en-delays.txt
# WebP, not GIF: the window's blurred arch bands in a GIF's 256 colours.
magick -loop 0 "${in[@]}" -resize 760x -quality 85 -define webp:method=6 "$media/demo.webp" < /dev/null
ls -la "$media"
