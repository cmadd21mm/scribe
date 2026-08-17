#!/bin/sh
set -eu

forbidden='URLSession|URLSessionTask|NWConnection|import[[:space:]]+Network|CFNetwork|downloadAndLoad|ModelHub\.download|AsrModels\.download|https?://'

matches="$({ grep -EnR --include='*.swift' "$forbidden" Sources/Scribe || true; } \
    | grep -v '^Sources/Scribe/CLI/ModelsCommand.swift:' \
    | grep -v 'xmlns="http://www.w3.org/2000/svg"' || true)"

if [ -n "$matches" ]; then
    echo "Runtime network API found outside the explicit model-download command:" >&2
    echo "$matches" >&2
    exit 1
fi

echo "No runtime network APIs outside ModelsCommand.swift."
