#!/bin/zsh
# How many people use Halftype, from GitHub's download counts: the app sends nothing of its own. Usage: scripts/usage.sh
#   dmg         downloads of Halftype.dmg: new installs from the site, README and Homebrew (where update is "-", Sparkle's updates too)
#   update      downloads of Halftype-update.dmg, the file Sparkle's appcast points to: installs that took this update
#   checks/day  appcast fetches per day while the release was the latest. Sparkle checks about once a day, so ~running installs
set -euo pipefail
gh api repos/hrsong99/halftype/releases --paginate | jq -rs '
  add | sort_by(.published_at) | . as $r | [range(length)] | map(
    $r[.] as $x | ($r[. + 1].published_at // (now | todate)) as $end
    | ((($end | fromdateiso8601) - ($x.published_at | fromdateiso8601)) / 86400) as $days
    | ($x.assets | map({(.name): .download_count}) | add // {}) as $a
    | [$x.tag_name, $x.published_at[:10], ($a["Halftype.dmg"] // $a["Itda.dmg"] // 0), ($a["Halftype-update.dmg"] // "-"),
       ($a["appcast.xml"] // 0), (($a["appcast.xml"] // 0) / ([$days, 1] | max) * 10 | round / 10)]
  ) | (["release", "date", "dmg", "update", "checks", "checks/day"], .[]) | @tsv' | column -t
