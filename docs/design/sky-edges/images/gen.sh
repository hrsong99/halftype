#!/bin/sh
# Remake one image idea: gen.sh G
set -e
here=$(cd "$(dirname "$0")" && pwd); L=$1; work=$(mktemp -d); cp "$here/today.png" "$work/"
{ printf 'Use your built-in image generation tool to create exactly 1 image from the prompt below\n(this is the approved image tool; if you are Codex, use it directly and do not run the codex binary).\nPass the prompt to the image tool as written; do not shorten or rephrase it.\nAfter generating, copy the image from wherever the tool saved it into the current\nworking directory, named exactly out.png. Do not create any other files.\n\n'; cat "$here/prompts/$L.txt"; } |
codex exec --skip-git-repo-check --ephemeral -c 'mcp_servers={}' -C "$work" -s workspace-write -i "$work/today.png" --add-dir ~/.codex/generated_images -
cp "$work/out.png" "$here/$L.png"
