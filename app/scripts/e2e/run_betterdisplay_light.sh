#!/bin/sh
# Live test of the BetterDisplay link against the REAL monitors (needs BetterDisplay Pro running with
# its notification integration on). It dims the displays and switches True Tone off for about a minute,
# then puts everything back (also switches the BetterDisplay group off and on). Not part of `swift test`; run it by hand when the monitors are free.
set -eu
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for f in Sources/IntermezzoKit/*.swift Sources/IntermezzoApp/Trace.swift Sources/IntermezzoApp/Light/BetterDisplayLight.swift Sources/IntermezzoApp/Light/AmbientSensor.swift; do
    grep -v '^import IntermezzoKit' "$f" > "$tmp/$(basename "$f")"
done
cp scripts/e2e/betterdisplay_light_main.swift "$tmp/main.swift"
swiftc -O -o "$tmp/e2e" "$tmp"/*.swift
"$tmp/e2e"
