#!/bin/zsh
# Image ideas C and D for the landing-page variants, with Codex's image tool. Usage: docs/site/ideas/gen.sh
set -euo pipefail
cd "${0:A:h}"
gen() {  # gen <letter> <prompt>
  work=$(mktemp -d); cp ../../media/window-field.png "$work/ref.png"
  codex exec -c 'mcp_servers={}' --skip-git-repo-check --ephemeral -C "$work" -s workspace-write -i "$work/ref.png" --add-dir ~/.codex/generated_images - <<EOF
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

$2
EOF
  magick "$work/out.png" -resize 1200x -quality 82 "$1.jpg"
}
gen c "$(cat c.prompt.txt)" & gen d "$(cat d.prompt.txt)" & wait
