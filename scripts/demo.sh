#!/bin/zsh
# Makes the README's pictures: docs/media/{en,ko}.gif from the real model, and the window's pages. Opens nothing on screen and takes no keys.
# Usage: scripts/demo.sh <gguf>
set -euo pipefail
cd "${0:A:h}/.."
args=(-c release -Xswiftc -enable-testing --disable-keychain --scratch-path .build/e2e --product itda-e2e)
swift build "${args[@]}" >/dev/null  # Or a failed build would make the pictures from the last one.
bin="$(swift build "${args[@]}" --show-bin-path)/itda-e2e"
frames=$(mktemp -d); media=$PWD/docs/media; mkdir -p "$media"
"$bin" --demo "$1" "$frames"
"$bin" --window-shots "$media"
cd "$frames"
for name in en ko; do
  in=(); while read -r file delay; do in+=(-delay "$delay" "$file"); done < "$name-delays.txt"
  magick -loop 0 "${in[@]}" -layers Optimize -resize 620x "$media/$name.gif" < /dev/null
done
ls -la "$media"
