#!/bin/bash
set -euo pipefail

# GitHub counts release asset downloads, including repeat downloads and updates.
page=1
while :; do
  releases=$(curl -fsSL "https://api.github.com/repos/cmadd21mm/scribe/releases?per_page=100&page=$page")
  [[ $(jq 'length' <<< "$releases") -gt 0 ]] || break
  jq -r '.[] | .tag_name as $tag | .assets[] | select(.name | endswith(".dmg")) | [$tag, .name, .download_count] | @tsv' <<< "$releases"
  ((page += 1))
done |
  awk -F '\t' '
    BEGIN { printf "%-16s %-32s %s\n", "RELEASE", "INSTALLER", "DOWNLOADS" }
    { printf "%-16s %-32s %s\n", $1, $2, $3; total += $3 }
    END { printf "%-49s %d\n", "TOTAL", total }
  '
