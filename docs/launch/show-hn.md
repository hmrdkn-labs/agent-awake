# Show HN draft: Agent Awake

Draft only, not posted. The owner edits, submits and answers the thread. Every factual sentence is in
Sources below.

Guidelines used (https://news.ycombinator.com/showhn.html): something people can run, not a landing
page; the author is around to discuss it; no signups needed to try it; no friends asked to upvote.

## Submission

- **Title** (53 characters, limit 80): `Show HN: Agent Awake, caffeinate for AI coding agents`
- **URL:** https://github.com/hmrdkn-labs/agent-awake
  - The repo, not the site. The guidelines say "Don't post landing pages". The download needs no signup
    (README:57-58).

## First comment (author, posted right after submitting)

Hi HN, I'm Dika, and I wrote Agent Awake. It is a macOS menu bar app that keeps your Mac awake while AI
coding agents work. When the last one finishes, the Mac can sleep again. If you're away from it, your
phone gets a ping.

I built it because leaving Claude Code, Codex or a long build running left me with two bad options: a Mac
that sleeps mid-task, or `caffeinate` burning battery all night.

How it works: each agent's own hooks report when a prompt starts, when the turn ends, and when the agent
needs you. While a session is alive, the app holds a power assertion of the kind `caffeinate -i` uses.
Lid-closed mode is optional and off by default: a small root helper switches `pmset disablesleep` and
gives sleep back at 10% battery, a serious thermal state, 41 °C, or a drain over 20% an hour.

Limits, so you can judge it: the 41 °C and 44 °C limits come from two days of logs on one MacBook Pro M4
Pro. The one bag trip I recorded, on version 0.1.2, took the battery from 100% to 59% in 75 minutes.
Before 0.1.3, a closed Mac could keep running after lid-closed mode had given up; 0.1.3 fixed that. It is
not in the Mac App Store, because its sandbox forbids the helper.

Feedback I'd like, starting with the root helper: read its scope in SECURITY.md and the lid-closed section
of the README, and check them against the code. Also whether the agent detection and the default ping
text fit how you work. Source is MIT and builds with `swift build && swift test`.

## Before you post

- Fix the helper's scope first. SECURITY.md:14 says the helper runs `pmset disablesleep` "and nothing
  else". README:176 and `Sources/AgentAwakeCore/SleepGuard.swift:14` also call `pmset sleepnow`. Make the
  docs match the code, or the first comment will be checked against the wrong text.
- Check that the link opens without an account, and that the latest release downloads.
- Submit when you can stay in the thread for the opening hours.

## Sources

- "caffeinate for AI agents" / "A macOS menu bar app" → README:12
- "Agents tell it when they start, finish and need you, through their own hooks" → README:12
- "When the last agent finishes, normal sleep comes back by itself" → README:36-37
- "your phone is pinged when you're away" → README:13, README:38-40
- "leaving Claude Code, Codex or a long build running ... caffeinate" → README:30-31
- "each agent's own hooks report when a prompt starts, when the turn ends, and when the agent needs you" → README:34-35
- "power assertion of the kind caffeinate -i uses, while a session is alive" → README:184-185
- "Lid-closed mode is optional and off by default" → README:163
- "a small root helper switches pmset disablesleep" → README:163-164, SECURITY.md:14-15
- "gives sleep back at 10% battery, a serious thermal state, 41 °C, or a drain over 20% an hour" → README:170-173
- "41 °C and 44 °C limits come from two days of logs on one MacBook Pro M4 Pro" → README:146-147, README:141
- "one bag trip ... 0.1.2, 100% to 59% in 75 minutes" → CHANGELOG.md:26-27
- "Before 0.1.3, a closed Mac could keep running after lid-closed mode had given up; 0.1.3 fixed that" → CHANGELOG.md:10-14
- "not in the Mac App Store, because its sandbox forbids the helper" → README:209-210
- "Source is MIT" → README:212-214
- "builds with swift build && swift test" → README:195
- "SECURITY.md:14 ... nothing else; code calls pmset sleepnow" → SECURITY.md:14, README:176, Sources/AgentAwakeCore/SleepGuard.swift:14
