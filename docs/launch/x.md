# X thread draft: Agent Awake

Draft only, not posted. Five posts. Each post is one blockquote line; the counts are in Report.

X counts every URL as 23 characters. Posts 1 and 5 have URLs. Counts are given both ways.

## Demo GIF (alt-text note)

- Where it goes: post 1, as the attached image. The file is `assets/screenshots/demo.gif`, 3 MB or less
  (`docs/launch/captures.md`, item 4, on branch `readme-top`; this branch has the same file).
- It does not exist in the repo yet. The owner records it on a real Mac (captures.md item 3: real time, no
  mock-ups). Do not post a placeholder GIF. If the clip is not ready, post the thread without it.
- Alt text, to check against the real clip before posting: "Screen recording, real time. Agent Awake's menu
  bar panel lists a Claude Code session while the agent works with the lid open, then the session leaves the
  panel when the agent finishes."

## Posts

### 1/5

> I built Agent Awake, a macOS menu bar app that keeps your Mac awake while AI coding agents work. When the last one finishes, the Mac can sleep again, and your phone gets a ping if you're away. Open source, MIT. https://agentawake.hamardikan.com/

### 2/5

> Why: leave Claude Code, Codex or a long build running and you get a Mac that sleeps mid-task, or one that burns battery all night on caffeinate. Agent Awake holds the Mac awake while work runs, then lets go.

### 3/5

> Agents report via their own hooks: start, done, needs you. Connect each in Settings → Agents; Disconnect removes exactly what Connect added. Hooks return at once, unless the Mac is hot or memory is almost full. Then the agent waits before its next tool call, up to 10 minutes.

### 4/5

> The one bag trip I recorded (version 0.1.2): battery 100% to 59% in 75 minutes. Lid-closed mode gives sleep back at 10% battery, a serious thermal state, 41 °C, or a drain over 20% an hour. The heat limits come from two days of logs on one MacBook Pro M4 Pro.

### 5/5

> Install: brew install --cask hmrdkn-labs/tap/agent-awake, or the DMG from the latest release. macOS 13 or later. Signed and notarized. Not in the Mac App Store, because its sandbox forbids the root helper. Code and feedback: https://github.com/hmrdkn-labs/agent-awake

## Sources

- Post 1: "menu bar app that keeps your Mac awake while AI coding agents work" → README:12-13, README:30-32; "sleep again" → README:36-37; "phone gets a ping if you're away" → README:38-40; "Open source, MIT" → README:212-214; site URL → README:15 (the Website link)
- Post 2: "leave Claude Code, Codex or a long build running ... burns battery all night on caffeinate" → README:30-31; "holds the Mac awake while work runs, then lets go" → README:36-37, README:43-44
- Post 3: "start, done, needs you ... through their own hooks" → README:34-35; "Connect each in Settings → Agents; Disconnect removes exactly what Connect added" → README:74-75; "Hooks return at once" → README:75-77; "unless the Mac is hot or memory is almost full ... waits before its next tool call, up to 10 minutes" → README:140, README:142, README:152
- Post 4: "bag trip (version 0.1.2): 100% to 59% in 75 minutes" → CHANGELOG.md:26-27; "gives sleep back at 10% battery, a serious thermal state, 41 °C, or a drain over 20% an hour" → README:170-173; "two days of logs on one MacBook Pro M4 Pro" → README:146-147
- Post 5: "brew install --cask hmrdkn-labs/tap/agent-awake" → README:61; "DMG from the latest release" → README:57-58; "macOS 13 or later" → README:64; "Signed and notarized" → README:21; "Not in the Mac App Store, because its sandbox forbids the root helper" → README:209-210; repo URL → README:6, README:15

## Before you post

- Demo GIF: record it, cut it to 3 MB or less, and check the alt text against the clip.
- Post 4 is the honest hook. Keep the bag-trip numbers and the one-machine note together.
