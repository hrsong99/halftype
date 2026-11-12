#!/bin/sh
# Usage: images/gen.sh I  (prompt from prompts/I.txt, reference today-*.png)
set -e; cd "$(dirname "$0")"; L=$1; work=$(mktemp -d)
ref=today-models.png; [ "$L" = J ] && ref=today-try-it.png
cp "$ref" "$work/ref.png"
{ printf 'Use your built-in image generation tool to create exactly 1 image from the prompt below (this is the approved image tool; do not run the codex binary). Pass the prompt to the image tool as written. After generating, copy the image into the current working directory, named exactly out.png. Do not create any other files.\n\n'; cat prompts/$L.txt; } |
codex exec --skip-git-repo-check --ephemeral -c 'mcp_servers={}' -C "$work" -s workspace-write -i "$work/ref.png" --add-dir ~/.codex/generated_images -
magick "$work/out.png" -quality 85 "$L.jpg"
