#!/bin/zsh
# End-to-end checks in a private window. It never becomes the frontmost app, but it does hold keyboard focus: keys the
# user types during a run land in it and are lost, and it interrupts their cursor. Ask the user before running it: the wait
# below for 60 s without a key press doesn't mean they have stopped using the Mac. Needs Accessibility.
# Flags: --ime (live Korean 2-set, needs you idle for 15 s), --flicker, --stale, --races, --engine <gguf>, --measure <gguf>, --shots <dir>.
set -euo pipefail
cd "${0:A:h}/.."
# Optimised, as it is measured, and testable, as it reaches into the app.
args=(-c release -Xswiftc -enable-testing --disable-keychain --scratch-path .build/e2e --product itda-e2e)
# A failed build stops here (pipefail), or the checks would run the last build's binary.
swift build "${args[@]}" 2>&1 | { grep -E "error|warning: unre|Build complete" || true; }
bin="$(swift build "${args[@]}" --show-bin-path)/itda-e2e"
# --ime selects the Korean source, which reaches the whole system. Whatever happens to the run, it goes back.
while (( $("$bin" --key-idle) < 60 )); do sleep 5; done
source_before=$("$bin" --source-id)
trap '"$bin" --set-source "$source_before"' EXIT INT TERM
perl -e 'alarm shift; exec @ARGV' "${ITDA_E2E_SECONDS:-300}" "$bin" "$@"
