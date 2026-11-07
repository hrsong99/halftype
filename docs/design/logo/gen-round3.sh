#!/bin/zsh
# Codex image-tool takes for the logo round, one call per prompt in prompts-round3.txt, the app look (I) as reference.
set -u; here=${0:A:h}
for id in r3a r3b r3c r3d r3e r3f r3g r3h; do (
  prompt=$(awk -v id="@$id" '$0==id{f=1;next} /^@/{f=0} f' "$here/prompts-round3.txt")
  work=$(mktemp -d); cp "$here/images/app-look-I.png" "$work/ref.png"
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
