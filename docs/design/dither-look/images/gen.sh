#!/bin/zsh
# Usage: gen.sh <letter> — sends prompts/<letter>.txt to Codex's image tool with today.png as reference, writes <letter>.png
here=${0:A:h}; l=$1; work=$(mktemp -d); cp $here/today.png $work/
{ cat <<'EOF'
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

EOF
cat $here/prompts/$l.txt; } | codex exec --skip-git-repo-check --ephemeral -c 'mcp_servers={}' -C $work -s workspace-write -i $work/today.png --add-dir ~/.codex/generated_images - > $work/log.txt 2>&1
cp $work/out.png $here/$l.png && echo "$l done" || { echo "$l failed"; tail -5 $work/log.txt; }
