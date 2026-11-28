# Reddit drafts: Agent Awake

Drafts only, not posted. Rewrite each post in your own words before you post it: Reddit's filters remove
AI-sounding text (r/macapps Phase 4 FAQ names em dashes; these drafts have none). Do not post the same text
to both subreddits.

## Subreddit rules, read before posting

**Read status.** The sidebar and wiki pages could not be read. reddit.com returns a bot challenge (HTTP 403)
to the reader, and old.reddit.com redirects to login. The rules below come from moderator posts, read through
the Arctic Shift archive, which is how the reader reached Reddit. Re-check each sidebar before posting.

### r/macapps

Primary: "r/MacApps Moderation Update (Phase 4): Clearer Rules, PCP+Trust", u/Mstormer, 2026-11-05
(reddit.com/r/macapps/comments/1xo5ky1). It replaces Phase 3.

- **Main feed:** account 300+ Reddit karma and 60+ days old; a pricing flair; four labels in the post:
  Problem, Comparison, Pricing, Trust.
- **Trust, one route:** Mac App Store; Developer Flair (500+ r/MacApps karma, mod review by modmail); GitHub
  with 100+ stars, or a LinkedIn link in the post; or Website with LinkedIn and privacy-policy links, and
  signed and notarized.
- **Saturated categories** include "Menu bar system and battery monitors". Those reach the main feed only
  through the Mac App Store or Developer Flair, unless the app places top 3 in The App Pile. The owner
  decides how to file this app.
- **The App Pile:** the monthly megathread. One entry per developer per month, with Problem, Comparison and
  Pricing labels.
- **Limit:** one app post per developer per 30 days, counted even when removed.
- **Open source:** prefix the title `[OS]`. Links: official sources only (GitHub counts).
- **Comparison label:** name 2 top competitors and say where they are still better. This conflicts with the
  brief's "no competitor names". See Report.
- **Repeat removals:** a second self-promotion removal within 90 days means a 60-day break.

### r/ClaudeAI

Nothing below comes from the sidebar; it could not be read.

- **Rule 7**, mod announcement 2026-01-16 (reddit.com/r/ClaudeAI/comments/1qe5wtt, Arctic Shift copy, marked
  "Removed by moderator" but holding the announcement text): "Claude must be the star", meaning the project
  was "built/designed largely by Claude or Claude Code"; say what you built and how Claude helped; the base
  project must be free to try (paid tiers are fine); no affiliate or referral links; keep marketing speak
  minimal.
- **Feed showcases:** the OP needs 50+ total karma. Below that, the Built with Claude Project Showcase
  megathread is the place (Showcase Discussion Hub, 2026-10-24, reddit.com/r/ClaudeAI/comments/1xe6tq7).
  The megathread also requires Rule 7.
- **Third-party guide, unverified:** "Showcase projects built with Claude with explanation of how it was
  used" (intoru.ai/subreddits/claudeai, search snippet only). PulseFox, another guide, has shut down.

**Blocker for variant B:** Rule 7 needs a true answer about Claude's role in building Agent Awake. The repo
history does not record one (one commit message mentions Claude Code, about site copy). The owner writes that
paragraph. The draft does not claim it.

## Variant A: r/macapps

Title (under 300 characters): `[OS] Agent Awake: keeps your Mac awake while AI coding agents work`

**Problem:** Leaving an AI coding agent or a long build running means your Mac either sleeps mid-task, or
burns battery all night on `caffeinate`.

**Comparison:** [OWNER DECISION: r/macapps requires two named competitors and where they are still better.
The brief bans competitor names. Choose before posting; see Report.]

**Pricing:** The app has no paid option, and its source is MIT: https://github.com/hmrdkn-labs/agent-awake
[Pricing flair: owner picks. The mods rank Lifetime > Subscription > Free, and "if any paid option exists,
it's not Free". Pushover's one-time $5 is a third-party ping service, not the app.]

**Trust:** [OWNER DECISION: pick one route from the rules above and fill in its label; see Report.]

I built Agent Awake because leaving a coding agent running left two bad options. Either the Mac sleeps
mid-task, or `caffeinate` keeps it awake all night and the battery drains.

What it does:

- Agents tell it when they start, finish and need you, through their own hooks. Connect each one in
  Settings → Agents. Disconnect removes exactly what Connect added, and a backup of each edited file is kept.
- The Mac stays awake while work runs. When the last agent finishes, normal sleep comes back. The screen still
  turns off and locks.
- When you're away, pings go to your phone through ntfy, Bark, Pushover, Telegram, Discord or Slack. By
  default a ping names the agent and the project folder, not your prompt.
- When the Mac runs hot, agents wait before their next tool call, up to 10 minutes per call. The limits come
  from two days of logs on one MacBook Pro M4 Pro, so treat them as a starting point.
- Lid-closed mode is optional and off by default. A small helper runs as root to switch sleep off. It gives
  sleep back at 10% battery, a serious thermal state, 41 °C, or a drain over 20% an hour.

What it does not do yet:

- It is not in the Mac App Store. The store's sandbox forbids the privileged helper.
- The one bag trip I recorded (version 0.1.2) took the battery from 100% to 59% in 75 minutes. Version 0.1.3
  fixed a case where a closed Mac kept running after the mode had given up.

Install: `brew install --cask hmrdkn-labs/tap/agent-awake`, or the DMG from the latest release. macOS 13 or
later. Signed with Developer ID and notarized by Apple.

I'd like feedback on the root helper and on the ping defaults. I'll answer questions here.

### Sources, variant A

- "Agents tell it when they start, finish and need you, through their own hooks" → README:12, README:34-35
- "Connect each one in Settings → Agents. Disconnect removes exactly what Connect added" → README:74-75
- "a backup of each edited file is kept" → SECURITY.md:18-19
- "The Mac stays awake while work runs ... normal sleep comes back ... screen still turns off and locks" → README:36-37
- "ntfy, Bark, Pushover, Telegram, Discord or Slack" → README:119-125
- "By default a ping names the agent and the project folder, not your prompt" → README:127-128
- "agents wait before their next tool call, up to 10 minutes per call" → README:140
- "limits come from two days of logs on one MacBook Pro M4 Pro" → README:146-147
- "Lid-closed mode is optional and off by default" → README:163
- "A small helper runs as root to switch sleep off" → README:163-164, SECURITY.md:14-15
- "gives sleep back at 10% battery, a serious thermal state, 41 °C, or a drain over 20% an hour" → README:170-173
- "not in the Mac App Store ... sandbox forbids the privileged helper" → README:209-210
- "one bag trip ... version 0.1.2 ... 100% to 59% in 75 minutes" → CHANGELOG.md:26-27
- "Version 0.1.3 fixed a case where a closed Mac kept running" → CHANGELOG.md:12-14
- "Install: brew ... DMG from the latest release" → README:57-61
- "macOS 13 or later. Signed with Developer ID and notarized by Apple" → README:21, README:64
- "The app has no paid option" → README:212-214 (MIT), and a code search of Sources, Resources and scripts found no StoreKit, purchase, paywall or license-key code (run on this branch; no line number)
- "Pushover's one-time $5" → README:123
- "Problem" line → README:30-31

## Variant B: r/ClaudeAI

Title (under 300 characters): `Agent Awake: keeps your Mac awake while Claude Code works, then lets it sleep`

[OWNER, required by Rule 7: say how Claude or Claude Code helped build this, truthfully. This draft does not say
it. Do not post until that paragraph is true.]

Agent Awake is a menu bar app for macOS. Claude Code is one of the agents it watches. Connect it in Settings →
Agents, or with `agentawake connect claude`. While a Claude Code turn runs, the Mac stays awake. When the turn
ends, normal sleep comes back. If you're away, a ping goes to your phone, by default something like "Claude
Code · shop is done", which names the agent and the folder.

When Claude Code needs you, for example at a permission prompt, the ping says so, and the Mac stays awake 15
more minutes so you can answer from your phone.

The hooks sit next to your own. Connect adds them and keeps a backup of the file. Disconnect removes exactly what
Connect added. The hooks print nothing and return at once, except when the Mac is hot or its memory is almost full. Then
Claude Code waits before its next tool call, up to 10 minutes.

Before you install:

- Lid-closed mode is off by default. It needs one approval in Login Items. It gives sleep back at 10% battery,
  a serious thermal state, 41 °C, or a drain over 20% an hour.
- The heat limits come from two days of logs on one MacBook Pro M4 Pro.
- It is not in the Mac App Store, because its sandbox forbids the root helper.

Download: the DMG from the latest GitHub release, or `brew install --cask hmrdkn-labs/tap/agent-awake`. macOS 13
or later. Source is MIT: https://github.com/hmrdkn-labs/agent-awake

Question for this sub: does the Claude Code setup match how you run Claude Code (CLI, desktop app, or IDE)?

### Sources, variant B

- "menu bar app for macOS" → README:12
- "Claude Code is one of the agents it watches" → README:81 (Claude Code row, id `claude`)
- "Connect it in Settings → Agents, or with agentawake connect claude" → README:74
- "While a Claude Code turn runs, the Mac stays awake ... normal sleep comes back" → README:36-37
- "by default ... 'Claude Code · shop is done' ... names the agent and the folder" → README:127-128
- "When Claude Code needs you ... stays awake 15 more minutes" → README:41-42, README:81
- "The hooks sit next to your own. Connect adds them and keeps a backup. Disconnect removes exactly what Connect added" → README:74-75
- "print nothing and return at once" → README:75-77
- "except when the Mac is hot or memory is almost full ... waits before its next tool call, up to 10 minutes" → README:140, README:142, README:152
- "Lid-closed mode is off by default ... one approval in Login Items" → README:163, README:166-167
- "gives sleep back at 10% battery ... drain over 20% an hour" → README:170-173
- "heat limits come from two days of logs on one MacBook Pro M4 Pro" → README:146-147
- "not in the Mac App Store, because its sandbox forbids the root helper" → README:209-210
- "DMG from the latest GitHub release; brew line; macOS 13 or later; Source is MIT" → README:57-61, README:64, README:212-214
- "CLI, desktop app, or IDE" → README:81

## Report notes for the owner

- Variant A needs a Comparison label (two named competitors) and a Trust route. Both are owner decisions.
- Variant B cannot be posted until the Rule 7 paragraph is true.
