#!/bin/zsh
# End-to-end checks in a private window that never takes focus. Needs this terminal to hold Accessibility.
set -euo pipefail
cd "${0:A:h}/.."
args=(--product Itda -Xswiftc -DITDA_E2E --scratch-path .build/e2e)
swift build "${args[@]}" 2>&1 | grep -E "error|Compiling ItdaApp|Build complete" || true
perl -e 'alarm 120; exec @ARGV' "$(swift build "${args[@]}" --show-bin-path)/Itda" "$@"
