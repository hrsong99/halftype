#!/bin/sh
# One Codex image per letter: ./gen.sh I J K  (prompt = prompts/common.txt + prompts/<L>.txt, refs = ../images/icon.png, ../built/16-stats-week.png)
here=$(cd "$(dirname "$0")" && pwd)
for L in "$@"; do (
  work=$(mktemp -d)
  cp "$here/../images/icon.png" "$work/ref-icon.png"; cp "$here/../built/16-stats-week.png" "$work/ref-week.png"
  { printf 'Use your built-in image generation tool to create exactly 1 image from the prompt below (this is the approved image tool; don'"'"'t run the codex binary).\nPass the prompt to the image tool as written; do not shorten or rephrase it.\nAfter generating, copy the image from wherever the tool saved it into the current working directory, named exactly out.png. Do not create any other files.\n\n'; cat "$here/prompts/common.txt" "$here/prompts/$L.txt"; } |
  codex exec --skip-git-repo-check --ephemeral -c 'mcp_servers={}' -C "$work" -s workspace-write -i "$work/ref-icon.png" -i "$work/ref-week.png" --add-dir ~/.codex/generated_images - > "$work/log" 2>&1
  [ -f "$work/out.png" ] && cp "$work/out.png" "$here/$L.png" && echo "$L done" || echo "$L failed: $work/log"
) & done; wait
