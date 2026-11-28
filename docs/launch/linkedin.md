# LinkedIn draft: Agent Awake

Draft only, not posted. One post, plain text, below. The count is in Report.

```text
I built Agent Awake, a macOS menu bar app. The code is on GitHub under the MIT license.

Coding agents like Claude Code and Codex can run for a long time. Walk away, and your Mac either sleeps mid-task, or burns battery all night on caffeinate.

Agent Awake keeps the Mac awake while agents work, then lets it sleep. Each agent reports through its own hooks. Away from the Mac, your phone gets a ping that names the agent and the project folder, not your prompt.

The part I want to be honest about is lid-closed mode. It is off by default. A small root helper switches sleep off, and gives sleep back at 10% battery, at a serious thermal state, at a battery temperature above 41 °C, or when the battery drains faster than 20% an hour.

The one bag trip I recorded (version 0.1.2) took the battery from 100% to 59% in 75 minutes. Version 0.1.3 fixed a case where a closed Mac kept running after the mode had given up. The heat limits come from two days of logs on one laptop, so treat them as a starting point.

macOS 13 or later, signed and notarized by Apple. Not in the Mac App Store: the store's sandbox does not allow the helper.

brew install --cask hmrdkn-labs/tap/agent-awake

https://github.com/hmrdkn-labs/agent-awake

If you run coding agents on a Mac, I'd like to hear what breaks.
```

## Sources

- "small macOS menu bar app" → README:12
- "MIT license" → README:212-214
- "Coding agents like Claude Code and Codex can run for a long time ... sleeps mid-task ... burns battery all night on caffeinate" → README:30-31
- "keeps the Mac awake while agents work, then lets it sleep" → README:36-37
- "Each agent reports through its own hooks" → README:34-35
- "your phone gets a ping that names the agent and the project folder, not your prompt" → README:38-40, README:127-128
- "lid-closed mode ... off by default" → README:163
- "A small root helper switches sleep off" → README:163-164, SECURITY.md:14-15
- "gives sleep back at 10% battery, at a serious thermal state, above 41 °C, or a drain faster than 20% an hour" → README:170-173
- "one bag trip ... version 0.1.2 ... 100% to 59% in 75 minutes" → CHANGELOG.md:26-27
- "Version 0.1.3 fixed a case where a closed Mac kept running after the mode had given up" → CHANGELOG.md:10-14
- "heat limits come from two days of logs on one laptop" → README:146-147
- "macOS 13 or later, signed and notarized by Apple" → README:21, README:64
- "Not in the Mac App Store: the store's sandbox does not allow the helper" → README:209-210
- "brew install --cask hmrdkn-labs/tap/agent-awake" → README:61
- "The code is on GitHub" → README:57-58 (release page on the repo)

## Before you post

- The bag trip is the honest hook. Keep it as one recorded trip; do not add trips you have not recorded.
- Check the repo link opens before posting.
