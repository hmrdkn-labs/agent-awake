# Security

Agent Awake includes a privileged helper (for lid-closed mode) and writes hooks into other tools'
config files, so security reports are taken seriously.

## Reporting

Please report vulnerabilities privately through
[GitHub security advisories](https://github.com/hmrdkn-labs/agent-awake/security/advisories/new),
not in public issues. Expect a first answer within a few days.

## What the app does with privileges

- The helper runs as root and runs only `/usr/bin/pmset` with fixed arguments: `disablesleep 1|0` for
  lid-closed mode, and `sleepnow` when lid-closed mode has ended with the lid closed and macOS would
  normally sleep on lid close (not with an external display in use).
- It exposes three XPC calls: `acquire(leaseSeconds)`, `release()` and `version()`. It accepts a
  connection only from a client signed by Apple's chain with the app's bundle ID and the helper's own
  Team ID. It refuses to run if it has no Team ID.
- Each `acquire` is a lease of at most 120 seconds, so the app must renew it. The helper turns
  `disablesleep` off again when the lease runs out, `release()` is called, the app's connection ends
  (quit or crash), the battery is at 10% or lower on battery power, or the thermal state is serious or
  critical. It also refuses `acquire` in the last two cases. A marker file
  (`/var/db/com.hamardikan.agent-awake.sleep-disabled`) lets a restarted helper undo a setting a crash
  left on.
- Hooks Connect adds to agents run `~/.agent-awake/bin/agentawake hook <agent> <event>` and always exit 0.
  They never print an allow or deny decision. Most print nothing. Cursor's prompt hook and Antigravity's
  hooks print a fixed JSON reply (`{"continue":true}`, `{}` or `{"decision":"stop"}`). Claude Code,
  Codex and Gemini CLI hooks print a `systemMessage` note only after they held a tool call.
- A tool-call hook waits while the Mac is hot or memory is almost full (setting "hold when strained",
  on by default), polling the app every 3 seconds for at most 600 seconds (less where the agent caps
  hook timeouts). Then the tool runs. If the app is unreachable or errors, it runs at once.
- Disconnect removes the hook entries Connect added (those whose command contains `agentawake hook`).
  The first time Connect edits an existing file it keeps a copy as `<file>.agentawake-backup`;
  Disconnect does not delete that copy.
- Channel credentials live in `~/.agent-awake/config.json`, mode 0600, in a 0700 folder. Channel
  error logs name the channel and an HTTP status or network error code, not the credentials.
