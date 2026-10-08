# Contributing

Pull requests are welcome: fork, branch off `master`, open a PR. `master` is protected; every change goes through a
reviewed PR.

- Build and test: `swift build && swift test`. Run your change: `./install.sh` rebuilds and restarts the app; watch
  `~/Library/Logs/ClaudeDictate.log`.
- Where things live and how to add a setting: [CLAUDE.md](CLAUDE.md).
- Don't bump `VERSION`: the maintainers cut a release after merging, and installed apps update themselves.
- Keep PRs focused: one fix or feature per PR, in the style of the surrounding code.
- Describe what you tested: which apps, AirPods or built-in mic, long dictations, Esc.
- The mod must pass `claude plugin validate mod`.
- Bugs and ideas: open an issue with your macOS and Claude Code versions (`claude --version`) and the log lines.
