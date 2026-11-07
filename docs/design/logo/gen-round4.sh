#!/bin/zsh
# Round 4: Codex image-tool takes, one call per prompt in prompts-round4.txt, each with its own reference images.
set -u; here=${0:A:h}
typeset -A refs=(
  r4a "images/r3c.png images/r3e.png"  r4b "images/r3c.png images/r3g.png"
  r4c "round3/Y.png images/r3c.png"    r4d "images/r3e.png"
  r4e "images/r3e.png images/r3g.png"  r4f "images/r3g.png"
  r4g "round3/Y.png"                   r4h "images/r3c.png round3/Y.png images/r3g.png"
)
for id in ${(k)refs}; do (
  prompt=$(awk -v id="@$id" '$0==id{f=1;next} /^@/{f=0} f' "$here/prompts-round4.txt")
  work=$(mktemp -d); args=()
  for r in ${=refs[$id]}; do cp "$here/$r" "$work/${r:t}"; args+=(-i "$work/${r:t}"); done
  codex exec --skip-git-repo-check --ephemeral -C "$work" -s workspace-write -c 'mcp_servers={}' $args --add-dir ~/.codex/generated_images - > "$work/log.txt" 2>&1 <<PROMPT
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

$prompt
PROMPT
  [[ -f "$work/out.png" ]] && { cp "$work/out.png" "$here/images/$id-raw.png"; echo "$id ok"; } || echo "$id FAILED $work/log.txt"
) & done; wait
