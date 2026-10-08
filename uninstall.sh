#!/bin/bash
# Removes the app, its login item, mod and state. The signing identity stays in the login keychain
# (Keychain Access → "ClaudeDictate Local Signing" to delete it).
set -uo pipefail
LABEL="local.claude-dictate"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null
pkill -x ClaudeDictate 2>/dev/null
rm -rf "$HOME/Applications/ClaudeDictate.app" "$HOME/Library/LaunchAgents/$LABEL.plist" \
  "$HOME/Library/Application Support/ClaudeDictate" "$HOME/Library/Logs/ClaudeDictate.log"
tccutil reset All "$LABEL" >/dev/null 2>&1
echo "ClaudeDictate removed"
