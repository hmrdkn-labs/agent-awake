# Security

Agent Awake includes a privileged helper (for lid-closed mode) and writes hooks into other tools'
config files, so security reports are taken seriously.

## Reporting

Please report vulnerabilities privately through
[GitHub security advisories](https://github.com/hmrdkn-labs/agent-awake/security/advisories/new),
not in public issues. Expect a first answer within a few days.

## What the app does with privileges

- The helper runs as root only to switch `pmset disablesleep` and nothing else. It accepts one XPC call,
  from clients signed with its own Team ID and the app's bundle ID, and restores normal sleep when the
  app's lease runs out, the battery reaches 10%, or the Mac gets hot.
- Hooks it adds to agents call `~/.agent-awake/bin/agentawake`, print nothing, always exit 0 and never
  change an agent's decisions. Disconnect removes exactly what Connect added; a backup of each edited
  file is kept as `<file>.agentawake-backup`.
- Channel credentials live in `~/.agent-awake/config.json` (mode 0600) and are never logged.
