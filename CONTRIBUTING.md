# Contributing

Pull requests are welcome: fork, branch off `main`, open a PR. `main` is protected; every change goes through a
reviewed PR.

- Build and run your change locally: `./install.sh` rebuilds and restarts the app; watch
  `~/Library/Logs/ClaudeDictate.log`.
- Keep PRs focused: one fix or feature per PR, in the style of the surrounding code.
- Describe what you tested: which apps, AirPods or built-in mic, long dictations, Esc.
- The mod must pass `claude plugin validate mod`.
- Bugs and ideas: open an issue with your macOS and Claude Code versions (`claude --version`) and the log lines.
