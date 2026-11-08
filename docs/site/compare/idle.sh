#!/bin/zsh
# Memory of a rival autocomplete app with no typing: start it hidden, sample each minute, quit it.
# Usage: idle.sh <path to .app> <process name> [minutes=8]. Prints: minute, footprint, RSS, CPU, whether a .gguf is mapped.
# Takes no keys or focus. Check first that no other copy of the app is running (pgrep -lf).
set -uo pipefail
app=$1 name=$2 minutes=${3:-8}
pgrep -x "$name" >/dev/null && { echo "$name is already running; not measuring a copy someone else started"; exit 1; }
id=$(defaults read "$app/Contents/Info" CFBundleIdentifier)
pid=""
stop() {  # Quit the app this script started, however the script ends, and say so only once it's gone.
  [ -n "$pid" ] || { [ -n "${launched:-}" ] && pid=$(pgrep -nx "$name"); } || return 0  # any copy is ours: none ran before we launched
  osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 $pid 2>/dev/null || break; sleep 1; done
  kill -0 $pid 2>/dev/null && kill $pid && sleep 2
  kill -0 $pid 2>/dev/null && { echo "$name ($pid) still running"; return 1; }
  echo "$name stopped"; pid=""
}
trap stop EXIT
trap 'exit 130' INT TERM
launched=1; open -g -j -a "$app"
for _ in $(seq 1 30); do pid=$(pgrep -nx "$name") && break; sleep 1; done  # found before the wait, so an interrupt still quits it
[ -n "$pid" ] || { echo "$name didn't start"; exit 1; }
sleep 45
sample() {
  fp=$(footprint -p $pid 2>/dev/null | awk '/Footprint:/{print $(NF-5)$(NF-4); exit}')
  rss=$(( $(ps -o rss= -p $pid) / 1024 ))
  cpu=$(top -l 2 -s 2 -pid $pid -stats cpu | tail -1)
  gguf=$(vmmap $pid 2>/dev/null | grep -c -i '\.gguf')
  echo "$1 footprint=$fp rss=${rss}MB cpu=$cpu% gguf_regions=$gguf"
}
sample 0.75min
for m in $(seq 1 $minutes); do sleep 56; sample ${m}.75min; done
