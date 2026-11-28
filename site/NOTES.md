# Agent Awake landing page: notes

Live: https://agentawake.hamardikan.com/ · Worker `agent-awake-site` (static assets only).
Planned 2026-11-25 from `~/workspace/sandbox/showcase-scan/research/agent-awake.md` and the repo.

## Concept

v2 (2026-11-25). The page runs **night to morning**. A Mac left working through the night: a dark room,
a tall window, one small warm light that means "still awake". Then a night train with the laptop in a
bag, a phone lighting up on a bedside table, and at the end the same desk at first light with the lid
closed. Direction: `~/workspace/sandbox/showcase-scan/build/v2/agent-awake/DIRECTION.md`.

### Reference

The skill in `build/v2/SKILL-gemini-frontend-design.md` and the owner's five points in `STANDARD.md`:
full-bleed hero type, two font families, a palette from the subject, custom images, no template chrome.

- **Hero:** image edge to edge from y = 0 behind a borderless header, h1 spanning the width over open
  night sky, one line of copy (19 words), one button. No stat strip, no install box.
- **Type:** Bricolage Grotesque 800 (display, wordmark, h2) and Instrument Sans 400 and 600 (body, labels,
  buttons, the brew command with `tabular-nums`). Both OFL, Latin subset woff2, self-hosted. Sizes below
  the hero: 2rem to 3.25rem (h2), 1.125rem (body, h3 in 600), 0.9375rem (captions, lists, notes, chart labels).
- **Colour:** `--bg #0b1a24`, `--surface #12283a`, `--text #e6eef2`, `--muted #9db2bf`, `--accent #f0a63a`
  (the one accent: button fill, focus ring, the battery dots and chord), `--dawn #dce6ec` with ink text
  and `--dawn-muted #3f5664`. Amber is never text on dawn (1.62:1). No gradients in CSS; light lives in the images.
- **Images:** four generated paintings (gouache style, shared style line), one per place; real captures stay real.

## Signature object: the bag-trip chart

One recorded trip (CHANGELOG.md 26–27, version 0.1.2): 75 minutes in a bag, battery 100% → 59%,
macOS thermal level "nominal" throughout, redrawn in the night palette as inline SVG, drawn 1:1
(700 or 300 units wide, 15px labels).

- Two recorded readings as amber dots (100% at 0 min, 59% at 75 min). The line between them is dashed
  and labelled "Two readings. Nothing in between was recorded." No curve is invented.
- A thin line for 20% an hour from 100%; a rule at the 10% floor; a band for macOS thermal level "nominal" (recorded, claim 10) and, below it, a dashed outline "serious: the stop rule, not reached" (the rule from claim 14; "not reached" follows from nominal throughout, claim 10).
- A separate battery temperature ruler (30–50 °C) with 41 °C hold, 44 °C pause and the author's ranges
  33–38 °C (desk) and 42–43.5 °C (bag). The caption says it is not a reading from this trip.
- Caption names version 0.1.2 and links CHANGELOG.md L26–L27 at the pinned commit.
- Static fallback: fully drawn in the markup; readings table and the four stop rules as a list beside it.
- Motion (once): the chord draws in 1.6 s when the chart first enters view, then the end labels appear.
  Reduced motion: nothing moves. Choosing a stop rule (a radio group, "All marks" first) highlights its mark; the serious-state rule highlights its own dashed row, never the nominal band. Without JS the radios are hidden and the rules read as a plain list.

## Page order

1. Skip link, borderless header (icon, wordmark, links Agents, In a bag, FAQ, Install, GitHub). Hero (image 1): h1, lede (claims 1, 2, 6, 29), one button, trust line with the brew command (claims 19, 21, 30).
2. Awake only while they work (claims 1, 3, 4).
3. Works with the agents you use: agent list with signals, the real Settings capture, hooks (claims 5–9, 26–27).
4. Sleep safeguards with the lid closed: claims 13–16, image 2 band, the chart, readings, four stop rules (claims 10–12, 14).
5. Pings only when you are away: image 3 (claims 2, 17, 18).
6. Questions (FAQ, native details): claims 31–36.
7. Install: download button, brew command with Copy, signing line, cask line, status (claims 19–25).
8. Open source, MIT on dawn with image 4 (claim 23).
9. More tools by hmrdkn-labs, on the night surface (claim 37). Footer: date, sha, repo, hamardikan.com.

## Image prompts (all with the shared style line)

Style line: "Quiet painterly illustration, matte gouache texture, deep marine night blues with one small warm amber
light, soft edges, no text, no logos, no visible screen UI, calm and still." Sources in `build/v2/agent-awake/art/`.

| # | Subject | Ratio | Used for |
|---|---|---|---|
| 1 | Laptop open on a wooden desk by a tall window at night, amber-white glow, small city low in the window, top 55% empty sky | 16:9 | Hero (phone: 3:4 crop from the right) |
| 2 | Closed laptop in a canvas messenger bag on a night train seat, streaks of light, one amber reading lamp | 3:2 | Bag band |
| 3 | Phone face up on a bedside table, blank screen glowing blue-white, glass of water | 2:3, cropped to 4:5 | Pings. First try came out peach, so the prompt asks for a cool blue-white screen and no cream or pink tint |
| 4 | Same desk at first light, closed laptop, mug, cool silver-blue sky, no amber (style line without the amber clause) | 16:9 | Closing band |

The image tool offers no 4:5, so image 3 is generated 2:3 and cropped. Hero export widths are 1536 (the
source width) and 1024; the tool does not make 2400.

## Revisions after review round 1

- M1: body prose is one size (1.125rem). 0.9375rem only for captions, citations, the cask and status lines, table cells and chart labels.
- M2: stop rules are a native radio group, not toggle buttons.
- M3: the serious thermal state has its own dashed mark; the nominal band is never highlighted.
- M4: heading "Sleep safeguards with the lid closed". No unqualified safety claim.
- S1: agents are grouped by signal set (start, finish and need you; start and finish), every name kept, no count.
- S2: narrow chart labels the 100% start dot; the 20% an hour label has a line swatch in clear space.
- S3: `verify.mjs` waits out the chart animation in desktop shots and writes `strip-desktop.png`, `strip-mobile.png` (reduced motion).
- N1: "when the battery temperature exceeds 41 °C". N2: footer says "Built", not "Maintained".

## Real vs missing

- Real: `assets/img/agents-*.webp` (Settings, Agents) and the app icon. Generated images are illustration only.
- Missing: a menu bar panel capture, a screen recording, a phone ping capture. Listed for Dika.

## Claims table

| # | Claim on the page | Source | Status |
|---|---|---|---|
| 1 | Keeps the Mac awake only while agents work; normal sleep returns when the last one finishes; the screen still turns off and locks. | README.md 28–29 | OK |
| 2 | Pings go to your phone only while you are away (idle, locked, lid closed); at the Mac you get a Mac notification. | README.md 30–32 | OK |
| 3 | When an agent needs you, the Mac stays awake 15 more minutes, then sleeps. | README.md 33–34 | OK |
| 4 | A quiet agent still running a build keeps the Mac awake; one whose process exited is let go. | README.md 35–36 | OK |
| 5 | The agent list (names). | `Sources/AgentAwakeCore/AgentCatalog.swift` lines 48–107, `AgentSpec(id:` entries | OK |
| 6 | Per-agent signal: start/done for all; "needs you" for the agents ticked in the README table. | README.md 71–90 | OK |
| 7 | Detected without setup: herdr panes, and oh-my-pi, Codex and Zed turns. | README.md 92–93 | OK |
| 8 | Connect adds hooks next to yours, keeps a backup; Disconnect removes exactly what it added. | README.md 66–67 | OK |
| 9 | Hooks report to the app without approving or denying tools; they normally return at once (the exception is claim 26); they do nothing if the app is not running. | README.md 68–69; `HookGate.swift` 3–12 (never decides; anything unexpected lets the tool run at once; waits only in the gate, up to `budget`), `AgentCatalog.swift` gates | OK, checked in code at 5df817d. Not claimed: "print nothing", because `HookAdapter.stdout` prints a fixed reply for Cursor and Antigravity and `heldStdout` prints a note for Claude Code, Codex and Gemini CLI after a hold |
| 10 | Trip: version 0.1.2, 75 minutes in a bag, battery 100% → 59% (41% of the battery), thermal level nominal throughout. | CHANGELOG.md 26–27 | OK (author's record) |
| 11 | 32.8% an hour on average over the trip (41 ÷ 1.25 h; arithmetic printed in "% of the battery"). | Derived from #10 | OK |
| 12 | Hold at battery 41 °C, pause at 44 °C. | CHANGELOG.md 15–16; README.md 132–133 | OK |
| 13 | Measured 33–38 °C at a desk, 42–43.5 °C after half an hour working in a bag; two days of log on a MacBook Pro M4 Pro. | README.md 138–139 | OK (author's measurement) |
| 14 | Lid-closed gives sleep back at 10% battery, when the thermal state is serious, above battery 41 °C, or on drain faster than 20% an hour. | README.md 162–165 | OK |
| 15 | Lid-closed mode is off by default; a helper you approve once in System Settings → Login Items. | README.md 155–159 | OK |
| 16 | When lid-closed mode gives up with the lid closed and macOS would normally sleep (no external display in use), the Mac sleeps; lid-closed mode then stays off until the lid opens. | README.md 166–169; CHANGELOG.md 12–14 | OK |
| 17 | Ping channels: ntfy, Bark, Pushover, Telegram, Discord, Slack. | README.md 111–117 | OK |
| 18 | By default a ping names only the agent and the project folder. | README.md 119–120 | OK |
| 19 | Signed with Developer ID and notarised by Apple; macOS 13 or later, Apple silicon or Intel. | README.md 56; cask `depends_on macos: :ventura` | OK |
| 20 | Updates itself; Settings → General turns that off. | README.md 58 | OK |
| 21 | `brew install --cask hmrdkn-labs/tap/agent-awake` installs 0.1.4. | README.md 53; cask version 0.1.4 (build checks it equals the latest release tag) | OK (clean-machine install not run: open question) |
| 22 | Latest release, its date; CI on main; last push; licence MIT. | `gh` at build time, stamped with the build date | OK (snapshot) |
| 23 | MIT licence; build from source with `swift build && swift test`. | LICENSE; README.md 184–185 | OK |
| 24 | Not in the Mac App Store, because its sandbox forbids the helper. | README.md 199–200 | OK |
| 25 | The Homebrew cask and the latest release are both the printed version, checked on the build date. | `gh` at build time; `build.sh` fails when they differ | OK (snapshot) |
| 26 | The one time hooks wait: the Mac is hot or almost out of memory; the agent pauses before its next tool call, up to ten minutes per call, then goes on. | README.md 132, 134, 144–147; `HookGate.swift` `budget = 600` | OK, checked in code |
| 27 | Antigravity, Cursor, Windsurf and Amp are not held. | README.md 144–147 | OK |
| 28 | Citations link to GitHub blob URLs pinned at commit 5df817d34c8b21b3b2fa51d54ec374c6bf40c268: CHANGELOG.md L26–L27, AgentCatalog.swift L48–L107, README.md L71–L90. | Lines read at that commit | OK |
| 29 | Hero lede: a menu bar app for macOS; agents report start, finish and "needs you" through their own hooks; the Mac stays awake only while they work; the phone is pinged when you are away. | README.md 26–27 (hooks: start, turn end, waiting), 28–31 (awake only while work runs; pings while away), 60–61 (menu bar app); claims 1, 2, 6 | OK |
| 30 | Hero trust line: signed with Developer ID and notarised by Apple · macOS 13 or later · the brew command. | Same as claims 19 and 21 | OK |
| 31 | FAQ battery: awake only while an agent works; the screen still turns off and locks to save battery; lid-closed mode gives sleep back at 10% battery, on a serious thermal state, above battery 41 °C or on drain above 20% an hour (the chart's four rules, claim 14); the recorded trip used 41% of the battery in 75 minutes. | README.md 28–29, 41–43, 162–165; claims 10, 14 | OK |
| 32 | FAQ lid closed: yes with lid-closed mode, off by default, helper approved once in System Settings → Login Items, runs only while work runs; heat is the real risk in a closed bag, prefer AC power; when it gives up with the lid closed and macOS would normally sleep, the Mac sleeps. | README.md 41–43, 155–159, 166–170 | OK |
| 33 | FAQ agents: Claude Code, Codex, Cursor and the others listed on the page; anything else reports through `agentawake`, for example `agentawake run build -- make all`. | README.md 95–98; claim 5 | OK |
| 34 | FAQ helper: macOS only lets a closed-lid Mac stay awake with root; root only to switch `pmset disablesleep` and, in one case, `pmset sleepnow`; accepts connections only from clients signed with the app's bundle ID and its own Team ID; each acquire is a lease of at most 120 seconds, renewed by the app every 30 seconds while work runs; `disablesleep` goes off when the lease runs out, the app quits or crashes, the battery is at 10% or lower, or the thermal state is serious. Links SECURITY.md pinned at 7c5570fbb5a53cf3379f109c7b245089ca0a2eeb (corrected version on local main). **That commit is not pushed yet, so the link 404s until it is.** | `SECURITY.md` 13–26 at 7c5570f; README.md 155–170; `Sources/AgentAwakeCore/LidGuard.swift` 7 (`renewEvery = 30`) | OK |
| 35 | FAQ what leaves: pings go only to the channels you set up; by default they name only the agent and project folder; updates are checked against a feed on GitHub; the one-minute strain log stays on your Mac. Not claimed: "no telemetry", "nothing goes to us" (not proven at runtime). | README.md 111–120, 138; `Resources/Info.plist` 16 `SUFeedURL` | OK |
| 36 | FAQ "How do I remove it?" was dropped. Disconnect removing hooks is claim 8, but nothing in the README or the UI shows how the helper or the app is removed (`HelperInstaller.unregister()` in `Helper.swift` 41 has no caller). | `Sources/AgentAwakeApp` (grep for `HelperInstaller.`) | NOT ON PAGE: open question for the owner |
| 37 | More tools by hmrdkn-labs: five sibling tools, names and one-line pitches verbatim, in order. Each pitch is condensed from that site's own title, meta description and h1 (read live 2026-11-28). | `~/workspace/sandbox/orchestration-2026-11-28/siblings.md` | OK (owner's ask) |


Left off the page (unresolved, research §8–9): any agent count; the word "free"; competitor
names; download or update-check counts; stars and forks (0).

## Search (v3)

Title, description, og/twitter text and the agents h2 now carry the query "keep Mac awake while AI agents work" and the named agents (SEO.md in the build folder has the research). JSON-LD `WebSite` + `SoftwareApplication` + `Person` in the head; `softwareVersion` comes from the release at build time and the line is dropped when none was read. The og image is `og.jpg` (87 KB). `sitemap.xml` is written by the build; `robots.txt` points to it; an IndexNow key file sits at the root (not submitted yet). CSP `connect-src` is `'self'` so Lighthouse can fetch robots.txt. No new product claims; not rich-result eligible (no ratings or offers, none invented).

## Revisions 2026-11-28 (marketing)

From `docs/briefs/marketing-audit.md` and the owner's decisions (no agent count, no "free", no competitors, no counts; no demo yet).

- Hero lede says what it is (a menu bar app for macOS) and what differs (hooks, awake only while working, phone ping). New trust line under the one button: signing, macOS 13, the brew command. The command is selectable in one tap; no Copy button in the hero, so the button stays the only one.
- The four paintings carry alt text starting "Illustration:" (also `og:image:alt`). None is decorative; the Settings capture keeps its UI description.
- New FAQ before Install: five questions, native `<details>`, no JS. "How do I remove it?" left off (claim 36).
- Footer `foot-more` line replaced by a "More tools by hmrdkn-labs" section on the night surface above the footer (claim 37). Whiteboard moved there from the footer line.
- Header nav gets "FAQ".
