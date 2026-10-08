#!/bin/bash
# Builds ClaudeDictate.app into ~/Applications, installs its Claude Code helper mod and starts it at login.
# Run again after pulling changes: it rebuilds and restarts the app.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/ClaudeDictate.app"
STATE="$HOME/Library/Application Support/ClaudeDictate"
LABEL="local.claude-dictate"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
IDENTITY="ClaudeDictate Local Signing"

[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ]] || { echo "macOS 26 or newer is required"; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc not found: run xcode-select --install"; exit 1; }
[[ -d "$HOME/.local/share/claude/versions" ]] || command -v claude >/dev/null ||
  { echo "Claude Code not found: https://code.claude.com/docs/en/setup"; exit 1; }

echo "building…"
mkdir -p build
swiftc -O -target "$(uname -m)-apple-macos26.0" -o build/ClaudeDictate Sources/main.swift 2> build/swiftc.log ||
  { grep -A3 "error:" build/swiftc.log; exit 1; }

# A stable self-signed identity keeps the Accessibility and Microphone permissions across rebuilds (an ad-hoc
# signature changes every build and macOS would ask again). It lives in the login keychain and signs only this app.
if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "creating the local signing identity \"$IDENTITY\"…"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 \
    -subj "/CN=$IDENTITY" -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
  openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:dictate 2>/dev/null ||
    openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:dictate
  security import "$tmp/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P dictate -T /usr/bin/codesign >/dev/null
fi

# stop the running copy (its hidden claude goes with it)
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
pkill -x ClaudeDictate 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp build/ClaudeDictate "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.claude-dictate</string>
  <key>CFBundleName</key><string>ClaudeDictate</string>
  <key>CFBundleExecutable</key><string>ClaudeDictate</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.2</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Claude Code voice dictation records while Fn is held.</string>
</dict></plist>
PLIST
codesign --force --sign "$IDENTITY" --identifier "$LABEL" "$APP"

# the mod sits outside the app bundle: Claude Code writes type stubs next to a plugin, which would break the seal
mkdir -p "$STATE"
rm -rf "$STATE/mod"
cp -R mod "$STATE/mod"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/ClaudeDictate</string></array>
  <key>RunAtLoad</key><true/>
  <!-- restart after a crash, not after Quit from the menu (clean exit) -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$UID" "$PLIST"

echo "installed $APP"
echo "first run: allow Accessibility and Microphone for ClaudeDictate when macOS asks, then hold Fn in any text field"
echo "log: ~/Library/Logs/ClaudeDictate.log"
