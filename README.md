# ClaudeDictate

System-wide voice dictation for macOS on top of Claude Code's `/voice`. Hold **Fn** in any text field, speak, and the
text is typed right where the caret is, live, as you talk. Release Fn and it settles on the final transcript.

- Works in any app with a text field: browsers, Slack, Telegram, editors, terminals.
- Live: words appear while you speak and get corrected in place to the final transcript.
- No time limit while Fn is held: Claude Code stops a recording after 2 minutes or 15 s of silence; ClaudeDictate
  picks up right after and keeps appending to the same text.
- Two indicators, picked in the menu bar menu: a Liquid Glass badge next to the pointer that reacts to your voice
  and ends with a check, a copy icon or a soft coral spin; or Claude Code's own `/voice` bar right of the text caret.
- No text field? Speak anyway: the text lands in the clipboard.
- **Esc** cancels and erases what this dictation typed.
- Costs nothing extra: per [Claude Code docs](https://code.claude.com/docs/en/voice-dictation), transcription "does not
  consume Claude messages or tokens and does not count toward the limits shown in `/usage`". The helper session never
  sends a prompt to the model.

Not affiliated with or endorsed by Anthropic.

## Requirements

- macOS 26 or newer (Apple silicon or Intel)
- [Claude Code](https://code.claude.com/docs/en/setup), signed in with a claude.ai account. Voice is not available with
  an API key, Bedrock, Vertex or Foundry. Tested with Claude Code 2.1.293.
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```sh
git clone https://github.com/maximcdq/claude-dictate-mac.git
cd claude-dictate-mac
./install.sh
```

The script builds `~/Applications/ClaudeDictate.app`, installs a login item and starts it. On first run allow
**Accessibility** and **Microphone** for ClaudeDictate when macOS asks (System Settings → Privacy & Security). A mic
icon appears in the menu bar.

The first time, macOS may also ask to let `codesign` use the "ClaudeDictate Local Signing" key: choose *Always Allow*.
That self-signed identity is created by the installer so macOS keeps your permissions across rebuilds.

To update: `git pull && ./install.sh`. To remove: `./uninstall.sh`.

Dictation language follows the `language` setting of Claude Code (`/config`, or `"language": "russian"` in
`~/.claude/settings.json`); see the [supported languages](https://code.claude.com/docs/en/voice-dictation#change-the-dictation-language).

## How it works

```
Fn held ──► ClaudeDictate.app ──spaces──► hidden `claude` in a pty (voice: hold mode)
                 ▲                                │ /voice streams audio to Anthropic,
                 │                                │ transcript lands in the prompt box
                 └──── live.txt ◄──── helper mod (Claude Code plugin) mirrors the prompt box
types the diff into the focused field
```

1. The app keeps one Claude Code session running in a hidden pseudo-terminal with voice dictation on.
2. While Fn is held it writes a steady stream of spaces into that terminal: to Claude Code that is a held Space,
   its push-to-talk key.
3. The helper mod in `mod/` (a Claude Code plugin with function hooks) mirrors the prompt box to `live.txt` every
   100 ms and drops any prompt submit, so nothing ever reaches the model.
4. The app types the text into the focused field through synthetic key events, erasing back to the common prefix and
   retyping whenever the transcript is revised.
5. When Claude Code ends a recording on its own (2 min / 15 s of silence) while Fn is still held, the app waits for
   that part's final text and starts the next recording, which appends to the same prompt.

Like any dictation app, it types into whatever has focus, in any app. Only when macOS reports that nothing there
takes text (the desktop, a page with no field active, a hidden window, an app with no window in sight) does the final
text go to the clipboard instead, with a copy icon on the badge. The same happens if focus moves to another field mid-dictation. Text that was typed
into a field leaves the clipboard untouched.

While dictating, the default input switches to the Mac's built-in mic so AirPods stay in high-quality audio mode; the
previous input is restored afterwards.

## Files

| Path | What |
|------|------|
| `Sources/main.swift` | the app: Fn event tap, hidden pty, typing, badge |
| `mod/` | Claude Code plugin running inside the hidden session |
| `install.sh` / `uninstall.sh` | build, sign, install / remove |
| `~/Library/Application Support/ClaudeDictate/` | state: `live.txt`, `control.txt`, the installed mod, the session's folder |
| `~/Library/Logs/ClaudeDictate.log` | log |

## Troubleshooting

- **Nothing happens on Fn**: check the log. `claude is still starting` shows during the first seconds after launch;
  `no text field in focus (…)` names what was focused when the text went to the clipboard instead. In System Settings → Keyboard set
  *Press 🌐 key to* "Do Nothing", or macOS will open the emoji picker / its own dictation.
- **`Voice mode requires a Claude.ai account`** in the log: run `claude` in a terminal and `/login`.
- **No permission prompts / typing doesn't work**: remove ClaudeDictate from Accessibility, run `./install.sh` again.

## Roadmap

- Choose the hotkey (currently Fn only)
- Settings in the menu bar: language, mic choice, autostart toggle

## License

MIT
