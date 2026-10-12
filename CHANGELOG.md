# Changelog

## Unreleased

- Heat and memory awareness. When the Mac runs hot or low on memory, agents wait before their next tool call
  until it recovers, and processes they started run at background priority. When memory is almost full, the
  largest process an agent started is paused until memory recovers (or stopped, or only reported).
- `agentawake strain [--wait]` for orchestrators and scripts.
- Keep awake presets also keep the screen on; agent work lets it sleep and lock.
- Existing hooks need Connect again for the new wait; Codex asks to trust the changed hook once.

## 0.1.0 (2026-10-11)

First release.

- Keeps the Mac awake only while AI agents work, with a menu bar panel showing what's running.
- One-click hooks for 19 agents: Claude Code, Codex, Gemini CLI, Antigravity, Qwen Code, Factory Droid,
  Augment, GitHub Copilot, Cursor, Windsurf, Devin Local, Kiro, Goose, Junie CLI, OpenCode, Kilo Code, Amp,
  oh-my-pi and pi, each shown with its own logo. herdr panes, and oh-my-pi, Codex and Zed turns, are detected
  without setup.
- Pings when an agent is done, needs you, or stops on an error: to your phone while you're away, as a Mac
  notification while you're at the Mac. Channels: ntfy, Bark, Pushover, Telegram, Discord, Slack.
- Pings name only the agent and project folder unless you opt in to task titles, since prompts can hold
  private text.
- A session that needs you keeps the Mac awake 15 minutes so you can answer remotely.
- Quiet agents still running a build stay awake; agents whose process exited are released at once.
- Optional lid-closed mode through a privileged helper, with battery and heat safety stops.
- `agentawake` command: `run`, `begin`/`beat`/`done`, `list`, `agents`, `connect`/`disconnect`, `settings`.
