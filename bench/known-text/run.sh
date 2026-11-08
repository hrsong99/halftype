#!/bin/bash
# Known-text benchmark: builds KnownText.swift as an extra target in a throwaway worktree (the app's Package.swift stays
# as it is), then runs each model in turn, one at a time, and prints the summary.
#   bench/known-text/run.sh [model.gguf ...]     default: the four in ~/Library/Application Support/Halftype
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
wt="${KNOWN_TEXT_WORKTREE:-$repo/../halftype-known-text}"
[ -d "$wt" ] || git -C "$repo" worktree add --detach "$wt" HEAD
mkdir -p "$wt/Sources/known-text"
cp "$here/KnownText.swift" "$wt/Sources/known-text/main.swift"
grep -q '"known-text"' "$wt/Package.swift" || sed -i '' 's|^    targets: \[|    targets: [\
        .executableTarget(name: "known-text", dependencies: ["HalftypeCore", "HalftypeEngine"]),|' "$wt/Package.swift"
# -enable-testing: the tool waits on the engine's internal finish().
(cd "$wt" && swift build --disable-keychain -c release -Xswiftc -enable-testing --product known-text)
[ -n "${BUILD_ONLY:-}" ] && exit 0
bin="$wt/.build/release/known-text"
models=("$@")
[ ${#models[@]} -gt 0 ] || models=("$HOME/Library/Application Support/Halftype/"{Qwen3.5-0.8B,Qwen3.5-2B}-Q4_K_M.gguf
    "$HOME/Library/Application Support/Halftype/kanana-1.5-2.1b-base.Q4_K_M.gguf" "$HOME/Library/Application Support/Halftype/gemma-4-E2B.Q4_K_M.gguf")
mkdir -p "$here/results"
for m in "${models[@]}"; do
    name="$(basename "$m" .gguf)"
    # $RUN_PREFIX: e.g. a one-model-at-a-time lock wrapper.
    /usr/bin/time -p ${RUN_PREFIX:-} "$bin" "$m" "$here/results/$name.jsonl" "$here"/{quotes,idioms,stock,articles}.txt
    gzip -f "$here/results/$name.jsonl"
done
python3 "$here/summarize.py" "$here/results"/*.jsonl.gz | tee "$here/results/summary.md"
