#!/bin/bash
# Builds ClaudeDictate.app into build/: the binary, Info.plist (version from VERSION), the icon and the helper mod.
# The bundle is left unsigned; install.sh signs it with the local identity, the release workflow ad hoc.
#   scripts/bundle.sh             this Mac's architecture
#   scripts/bundle.sh --universal arm64 + x86_64 (releases)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/ClaudeDictate.app"

ARGS=(-c release)
[[ "${1:-}" == "--universal" ]] && ARGS+=(--arch arm64 --arch x86_64)
swift build "${ARGS[@]}" >&2
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/ClaudeDictate"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeDictate"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# without the type stubs Claude Code writes next to the mod when it runs from the source tree
rsync -a --exclude .claude-plugin/types mod/ "$APP/Contents/Resources/mod/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.claude-dictate</string>
  <key>CFBundleName</key><string>ClaudeDictate</string>
  <key>CFBundleExecutable</key><string>ClaudeDictate</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Claude Code voice dictation records while the dictation key is held.</string>
</dict></plist>
PLIST
echo "$APP"
