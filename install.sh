#!/bin/bash
# Builds ClaudeDictate.app into ~/Applications, installs its Claude Code helper mod and starts it at login.
# Run again after pulling changes: it rebuilds and restarts the app.
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/ClaudeDictate.app"
LABEL="local.claude-dictate"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
IDENTITY="ClaudeDictate Local Signing"

[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ]] || { echo "macOS 26 or newer is required"; exit 1; }
command -v swift >/dev/null || { echo "swift not found: run xcode-select --install"; exit 1; }
[[ -d "$HOME/.local/share/claude/versions" ]] || command -v claude >/dev/null ||
  { echo "Claude Code not found: https://code.claude.com/docs/en/setup"; exit 1; }

echo "building…"
./scripts/bundle.sh > build.log 2>&1 || { grep -A3 "error:" build.log || tail -20 build.log; exit 1; }
rm -f build.log

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
mkdir -p "$(dirname "$APP")"
ditto build/ClaudeDictate.app "$APP"
codesign --force --sign "$IDENTITY" --identifier "$LABEL" "$APP"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/ClaudeDictate</string></array>
  <key>RunAtLoad</key><true/>
  <!-- restart after a crash or an update (a failing exit), not after Quit from the menu (clean exit) -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
# "Start at login" off in the app's settings disables the agent: then just start the app this once
if launchctl print-disabled "gui/$UID" | grep -q "\"$LABEL\" => disabled"; then
  open "$APP"
else
  launchctl bootstrap "gui/$UID" "$PLIST"
fi

echo "installed $APP"
echo "first run: allow Accessibility and Microphone for ClaudeDictate when macOS asks, then hold Fn in any text field"
echo "settings (hotkey, language, indicator, updates): the menu bar icon → Settings…"
echo "log: ~/Library/Logs/ClaudeDictate.log"
