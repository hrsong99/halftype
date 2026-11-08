#!/bin/zsh
# The typing comparison, start to end (README.md). It takes the keyboard, the pointer and the front window for about
# 50 minutes and switches input sources: start it when you're about to leave the Mac alone.
#   bench/compare/run.sh                       every app
#   bench/compare/run.sh --check               the preconditions only: types nothing, launches nothing
#   bench/compare/run.sh --apps halftype,keytype [--en 16] [--ko 10]
set -euo pipefail
cd "${0:A:h}/../.."
text=~/halftype-lab-private/compare/text
[[ -s $text/en.tsv && -s $text/ko.tsv ]] || python3 -I bench/compare/text.py fetch $text
# Optimised, as it times frames, and testable, as it borrows the app's 2-set table. Info.plist goes inside the binary,
# so the apps under test see an ordinary app with an ID, while, started from here, it keeps the terminal's permissions.
args=(-c release -Xswiftc -enable-testing --disable-keychain --scratch-path .build/compare --product halftype-compare
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker bench/compare/Info.plist)
swift build "${args[@]}" 2>&1 | { grep -E "error|Build complete" || true; }
exec "$(swift build "${args[@]}" --show-bin-path)/halftype-compare" --text $text "$@"
