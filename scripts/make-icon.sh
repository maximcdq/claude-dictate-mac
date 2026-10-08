#!/bin/bash
# Regenerates Resources/AppIcon.icns from the mark drawn in Sources/ClaudeDictate/App/MenuBarIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc -O -o "$tmp/make-icon" scripts/icon/main.swift Sources/ClaudeDictate/App/MenuBarIcon.swift
"$tmp/make-icon" "$tmp/AppIcon.iconset"
iconutil -c icns -o Resources/AppIcon.icns "$tmp/AppIcon.iconset"
[[ -n "${PREVIEW:-}" ]] && cp "$tmp/AppIcon.iconset/icon_512x512@2x.png" "$tmp"/menubar-*.png "$PREVIEW"
echo "Resources/AppIcon.icns"
