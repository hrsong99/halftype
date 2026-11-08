#!/bin/zsh
# One Codex image per direction, with today's General pane as reference. Usage: gen.sh <letter> <direction>
D=/Users/johnsong/code/side-projects/halftype/docs/design/settings-motion
work=$(mktemp -d); cp $D/today.png $work/
codex exec --skip-git-repo-check --ephemeral -c 'mcp_servers={}' -C "$work" -s workspace-write -i "$work/today.png" --add-dir ~/.codex/generated_images - <<P
Use your built-in image generation tool to create exactly 1 image from the prompt below
(this is the approved image tool; don't run the codex binary).
Pass the prompt to the image tool as written; do not shorten or rephrase it.
After generating, copy the image from wherever the tool saved it into the current
working directory, named exactly out.png. Do not create any other files.

A crisp macOS settings pane UI mockup, square 1:1, in the style of the attached screenshot: warm cream window, an off-white rounded pane, SF Pro text, black and grey type, segmented controls in light grey. The pane is titled "General" with rows Start at Login, Length (Short/Medium/Long), How Often (Less/Normal/More/Always). The design question is the setting for the small animation that plays at the text caret when the user presses Tab to accept an autocomplete suggestion; options Trail (a short blue-to-peach gradient underline streak trailing behind the caret), Flash (the caret briefly turns blue-to-peach) and Off. In today's version a tiny preview is squeezed inline into one row, pushing the label; redesign it so the setting has room. Direction: $2 Keep it calm, Apple-like and minimal, no extra decoration, legible text only.
P
cp $work/out.png $D/images/$1.png && echo done $1
