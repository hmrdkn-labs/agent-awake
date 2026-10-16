# Changelog

## Unreleased

- The app updates itself: it checks GitHub for new versions in the background and installs them in place
  (Sparkle 2, EdDSA-signed). Turn it off in Settings → General, or check now with "Check for Updates…".

## 0.1.3 (2026-10-16)

- Lid-closed mode now actually sleeps the Mac when it gives up with the lid closed (heat, fast drain, low
  battery, work done). Before, macOS kept a closed Mac awake once it had closed with the setting on: two
  bag trips ran on for 20 minutes and 2 hours, draining up to 32% an hour. It stays off until the lid opens.
- Heat limits lowered to battery 41 °C (hold) and 44 °C (pause), from two days of `strain.log`: 33-38 °C at
  a desk, 42-43.5 °C in a bag. The old 45 °C was never reached.
- Connecting an agent no longer drops its sessions that were already running: herdr panes and power
  assertions are skipped per pane and per process once those report through hooks, not per agent.
- `strain.log` records whether lid-closed mode is on.
- The release script no longer runs again at the next login after publishing.
- The lid-closed helper restarts itself when the app is updated; before, the old helper kept running until a
  reboot. Updating from 0.1.2 or earlier: restart the Mac once, so the new helper takes over.

## 0.1.2 (2026-10-13)

- Heat now uses the battery and chip temperatures, not only macOS's thermal level, which stayed "nominal"
  through a 75-minute trip in a bag while the battery fell from 100% to 59%. Battery 45 °C holds agents and
  slows their work; 50 °C also pauses everything agents started until it cools.
- Lid-closed mode turns itself off when the battery passes 45 °C or drains faster than 20% an hour, so a Mac in
  a bag goes to sleep.
- Memory "low" no longer holds agents: on a busy Mac it can last for hours. Only "almost full" does, and paused
  processes continue once memory has stayed below that for a minute.
- `~/.agent-awake/strain.log`: one line a minute of temperatures, pressure, battery and lid state.
- `agentawake strain` shows battery and chip temperatures.

## 0.1.1 (2026-10-12)

- Heat and memory awareness. When the Mac runs hot or low on memory, agents wait before their next tool call
  until it recovers, and processes they started run at background priority. When memory is almost full, the
  largest process an agent started is paused until memory recovers (or stopped, or only reported).
- `agentawake strain [--wait]` for orchestrators and scripts.
- Keep awake presets also keep the screen on; agent work lets it sleep and lock.
- Existing hooks need Connect again for the new wait; Codex asks to trust the changed hook once.
  Upgrading: open Settings → Agents and press Connect on agents marked out of date.

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
