#!/bin/zsh
# Codex image-tool takes for the logo round, one call per prompt in prompts.txt, today's icon as reference.
set -u; here=${0:A:h}
for id in g h i; do (
  prompt=$(awk -v id="@$id" '$0==id{f=1;next} /^@/{f=0} f' "$here/prompts.txt")
  work=$(mktemp -d); cp "$here/images/today.png" "$work/ref.png"
  codex exec --skip-git-repo-check --ephemeral -C "$work" -s workspace-write -c 'mcp_servers={}' -i "$work/ref.png" --add-dir ~/.codex/generated_images - > "$work/log.txt" 2>&1 <<PROMPT
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

$prompt
PROMPT
  [[ -f "$work/out.png" ]] && { cp "$work/out.png" "$here/images/$id-raw.png"; echo "$id ok"; } || echo "$id FAILED $work/log.txt"
) & done; wait
