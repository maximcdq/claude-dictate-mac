# ClaudeDictate: working on this repo

System-wide dictation for macOS on top of Claude Code `/voice`. Swift package, AppKit + a little SwiftUI, no
dependencies. Owner: maximcdq. Other people contribute through pull requests.

## Workflow (do it this way every time)

1. Every change goes through a PR into `master` (protected, the `build` check must pass). Our own work too: branch,
   PR, merge.
2. Review incoming PRs before merging: `gh pr checkout <n>`, read the diff, `swift build && swift test`,
   `./install.sh` and dictate in a couple of apps (a browser field, a terminal) when the change touches dictation,
   typing, the hotkey or the indicators. Merge only what works and keeps the current behavior.
3. **Right after a PR is merged, cut a release**: `scripts/release.sh <next version> "<notes for people>"` from an
   up-to-date `master` (patch for fixes, minor for features). It bumps `VERSION` and the mod's version, tags,
   pushes and publishes the GitHub release; `.github/workflows/release.yml` then attaches `ClaudeDictate.zip`.
   Check the asset landed (`gh release view v<version>`). Installed apps pick it up within hours (or Settings →
   Updates → Check Now) and restart into it.
4. Then update this Mac too: `./install.sh` (or let the app update itself and check the log).

## Layout

| Module | What |
|--------|------|
| `Sources/DictateCore` | paths, log, `Version`, `Hotkey` model, the settings store (`Setting`, `SettingsStore`); no UI |
| `Sources/DictateAnimations` | the indicators: `VoiceBadge`/`BadgeIndicator` (glass badge at the pointer), `CaretBar`/`CaretIndicator` (Claude Code's bar at the caret), `Easing`, `Palette`; mic level comes in through `LevelSource` |
| `Sources/DictateUpdater` | self-update from GitHub releases: download, SHA-256 check, re-sign with the local identity, swap the bundle |
| `Sources/ClaudeDictate` | the app: `Claude/` hidden session in a pty, `Audio/` mic switching and level meter, `Input/` hotkey event tap and synthetic typing, `Accessibility/` focus and caret lookup, `Dictation/` the state machine, `Settings/` keys and the settings window, `System/` login item and relaunch, `App/` menu bar |
| `mod/` | the Claude Code plugin inside the hidden session; shipped in the app bundle, copied to `~/Library/Application Support/ClaudeDictate/mod` at launch |
| `scripts/` | `bundle.sh` (build the .app), `release.sh`, `make-icon.sh` (regenerate `Resources/AppIcon.icns`) |

## Adding a setting

1. Declare it in `Sources/ClaudeDictate/Settings/AppSettings.swift`:
   `static var name: Setting<Type> { .init("name", default: …) }` (Bool, String or a String-backed enum).
2. Show it in a pane under `Settings/Panes/` with `settings.binding(.name)`; a new pane goes into
   `SettingsWindow.panes`.
3. Use it: read `settings[.name]` where needed, or `settings.observe(.name) { … }` to react to a change.

## Rules

- Don't break dictation: the timing constants, the Claude Code screen parsing and the typing logic encode behavior
  found by testing in many apps; change them only on purpose and test.
- The local signing identity ("ClaudeDictate Local Signing", made by `install.sh`) keeps macOS permissions across
  rebuilds and updates; don't change the bundle identifier or the signing identifier (`local.claude-dictate`).
- `VERSION` is the single source of the version; `scripts/release.sh` keeps `mod/.claude-plugin/plugin.json` in step.
- Log to `~/Library/Logs/ClaudeDictate.log` with `log(…)`; that's what bug reports quote.
