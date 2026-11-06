#!/bin/zsh
# End-to-end checks in a private window that never takes focus. Needs this terminal to hold Accessibility.
# Flags: --ime (live Korean 2-set, needs you idle for 15 s), --engine <gguf>, --measure <gguf>, --shots <dir>.
set -euo pipefail
cd "${0:A:h}/.."
# Optimised, as it is measured, and testable, as it reaches into the app.
args=(-c release -Xswiftc -enable-testing --disable-keychain --scratch-path .build/e2e --product itda-e2e)
swift build "${args[@]}" 2>&1 | grep -E "error|warning: unre|Build complete" || true
bin="$(swift build "${args[@]}" --show-bin-path)/itda-e2e"
# --ime selects the Korean source, which reaches the whole system. Whatever happens to the run, it goes back.
source_before=$("$bin" --source-id)
trap '"$bin" --set-source "$source_before"' EXIT INT TERM
perl -e 'alarm shift; exec @ARGV' "${ITDA_E2E_SECONDS:-300}" "$bin" "$@"
