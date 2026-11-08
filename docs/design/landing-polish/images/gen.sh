#!/bin/zsh
# Image ideas H, I, J for the landing-page polish round, with Codex's image tool. Usage: gen.sh [letters]
set -euo pipefail
cd "${0:A:h}"
gen() {
  work=$(mktemp -d); cp today.png "$work/today.png"; cp icon.png "$work/icon.png"
  codex exec -c 'mcp_servers={}' --skip-git-repo-check --ephemeral -C "$work" -s workspace-write -i "$work/today.png" -i "$work/icon.png" --add-dir ~/.codex/generated_images - <<EOF
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

$(cat $1.prompt.txt)
EOF
  magick "$work/out.png" -resize 1600x -quality 84 "$1.jpg"
}
(( $# )) || set -- H I J  # zsh keeps "${@:-H I J}" as one word
for l in "$@"; do gen $l & done; wait
