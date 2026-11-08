#!/bin/zsh
# Memory of a rival autocomplete app with no typing: start it hidden, sample each minute, quit it.
# Usage: idle.sh <path to .app> <process name> [minutes=8]. Prints: minute, footprint, RSS, CPU, whether a .gguf is mapped.
# Takes no keys or focus. Check first that no other copy of the app is running (pgrep -lf).
set -uo pipefail
app=$1 name=$2 minutes=${3:-8}
pgrep -x "$name" >/dev/null && { echo "$name is already running; not measuring a copy someone else started"; exit 1; }
open -g -j -a "$app"
sleep 45
pid=$(pgrep -nx "$name") || { echo "$name didn't start"; exit 1; }
sample() {
  fp=$(footprint -p $pid 2>/dev/null | awk '/Footprint:/{print $(NF-5)$(NF-4); exit}')
  rss=$(( $(ps -o rss= -p $pid) / 1024 ))
  cpu=$(top -l 2 -s 2 -pid $pid -stats cpu | tail -1)
  gguf=$(vmmap $pid 2>/dev/null | grep -c -i '\.gguf')
  echo "$1 footprint=$fp rss=${rss}MB cpu=$cpu% gguf_regions=$gguf"
}
sample 0.75min
for m in $(seq 1 $minutes); do sleep 56; sample ${m}.75min; done
osascript -e "tell application id \"$(defaults read "$app/Contents/Info" CFBundleIdentifier)\" to quit" >/dev/null 2>&1
sleep 5; pgrep -x "$name" >/dev/null && kill $pid
echo "$name stopped"
