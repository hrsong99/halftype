#!/bin/sh
# One Codex image per call (~/Synced/tooling-notes/codex-cli-image-gen.md). Usage: gen.sh <name> <prompt-file>
set -e
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); cp "$here/today.jpg" "$work/"
codex exec -c 'mcp_servers={}' --skip-git-repo-check --ephemeral -C "$work" -s workspace-write -i "$work/today.jpg" --add-dir ~/.codex/generated_images - <<END
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

$(cat "$2")
END
cp "$work/out.png" "$here/$1.png"
