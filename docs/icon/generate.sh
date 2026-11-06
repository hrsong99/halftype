#!/bin/zsh
# Generates the icon options with Codex's built-in image tool. One call per option; outputs land next to this script.
set -u
here=${0:A:h}
for id in a b c; do
  (
    prompt=$(awk -v id="@$id" '$0==id{f=1;next} /^@/{f=0} f' "$here/prompts.txt")
    work=$(mktemp -d)
    codex exec --skip-git-repo-check --ephemeral -C "$work" -s workspace-write -c 'mcp_servers={}' --add-dir ~/.codex/generated_images - > "$work/log.txt" 2>&1 <<PROMPT
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

$prompt
PROMPT
    if [[ -f "$work/out.png" ]]; then cp "$work/out.png" "$here/option-$id-raw.png"; echo "$id ok"; else echo "$id FAILED, see $work/log.txt"; fi
  ) &
done
wait
