#!/bin/sh
# Remake one image idea: gen.sh K   (Codex's built-in image tool, ~1 min)
set -e
here=$(cd "$(dirname "$0")" && pwd); L=$1
work=$(mktemp -d); cp "$here/${REF:-today.png}" "$work/ref.png"; [ -n "$REF2" ] && cp "$here/$REF2" "$work/ref2.png"
{ printf 'Use your built-in image generation tool to create exactly 1 image from the prompt below (this is the approved image tool; do not run the codex binary). Pass the prompt to the image tool as written; do not shorten or rephrase it. After generating, copy the image from wherever the tool saved it into the current working directory, named exactly out.png. Do not create any other files.\n\n'; cat "$here/prompts/$L.txt"; } |
codex exec --skip-git-repo-check --ephemeral -c 'mcp_servers={}' -C "$work" -s workspace-write -i "$work/ref.png" ${REF2:+-i "$work/ref2.png"} --add-dir ~/.codex/generated_images - >"$work/log" 2>&1
sips -Z 1000 -s format jpeg "$work/out.png" --out "$here/$L.jpg"
