# Agent Awake landing page: notes

Live: https://agentawake.hamardikan.com/ · Worker `agent-awake-site` (static assets only).
Planned 2026-11-25 from `~/workspace/sandbox/showcase-scan/research/agent-awake.md` and the repo.

## Concept

The page is a **chart-recorder printout of one bag trip**. Agent Awake's whole story is that a Mac
in a bag lied about its heat, so the app learned to read the battery and to give sleep back. The
page reads like the paper that comes out of a data logger: a ruled strip with a pen trace, a
caption with the instrument settings, and the operating notes printed underneath.

### Reference

Strip-chart recorder paper and cold-chain shipping data loggers: the receipt a temperature logger
prints after a trip (ruled grid, minute ticks along the edge, one pen colour per channel, a
stamped header with instrument and date). Honoured in:

- **Grid:** the page sits on a 12-column measure with a faint ruled minute grid only inside the
  strip, never as a page background. Sections are separated by a printed rule with a small
  channel label, like the edge of a recorder roll.
- **Type:** Source Serif 4 for reading (a lab report's body text), IBM Plex Mono for every label,
  axis, value and command (the recorder's printed scale). Both OFL, self-hosted, two families.
- **Colour:** paper (warm off-white) and graphite ink; one pen red for the battery channel; one
  pen blue-grey for the thermal channel. Night: graphite paper with light ink, the same two pens
  lifted to pass AA. No gradients, no glow.
- **Texture:** hairline rules, tick marks, a perforation edge drawn in SVG along the strip only.

## Signature object: the bag-trip strip

One recorded trip (CHANGELOG.md 26–27, version 0.1.2): 75 minutes in a bag, battery 100% → 59%,
macOS thermal level "nominal" throughout. Drawn as custom inline SVG, beside the four stop rules.

Channels on the strip (x axis: minutes 0–75, ticks every 15):

1. **Battery %** (pen red). Two recorded readings: 100% at 0 min, 59% at 75 min, as solid dots.
   The straight line between them is dashed and labelled "Two readings. Nothing in between was
   recorded." No curve is invented.
2. **Stop rule slope** (graphite, thin): 20% an hour from 100% (100 → 75 at 75 min). The trip's
   chord falls below it. Derived and labelled with its arithmetic: 41 points in 75 minutes is
   32.8% an hour on average (100 − 59 = 41; 41 ÷ 1.25 h = 32.8).
3. **Battery floor**: a rule at 10%.
4. **Thermal level** (pen blue-grey): a flat band across all 75 minutes labelled "nominal".
5. **Battery temperature scale** (separate short ruler beside the strip, 30–50 °C): ticks at 41 °C
   hold and 44 °C pause (CHANGELOG.md 15–16, README.md 132–133), with the author's measured ranges
   33–38 °C at a desk and 42–43.5 °C in a bag (README.md 138–139). Caption (revised in fix round 1):
   the ruler marks the limits and the author's measured ranges and is not a reading from this trip.
   The earlier wording ("0.1.2 used macOS's level only, which is why the limits came later") was
   dropped because CHANGELOG.md 0.1.2 says that release already added battery readings.

Caption names the build: "Version 0.1.2. One trip, recorded by the author. Source:
CHANGELOG.md, lines 26–27."

Static fallback: the SVG is fully drawn in the HTML, so JS off and reduced motion show the final
strip. A readings table (start, end, thermal level) and the four rules as a list sit under it as
the text version.

**Signature motion (once):** when the strip first enters view, the dashed battery chord draws from
100% to 59% over about 1.6 s, the 59% dot lands, then the "32.8% an hour" label appears. It does
not loop. Reduced motion: nothing moves.

**Micro-interactions (3):**
1. Pointing at or focusing a stop rule in the list highlights its mark on the strip (and the mark
   names the rule); works by tap on touch.
2. Copy button on the Homebrew command: text changes to "Copied" with an `aria-live` note; the
   command stays selectable without JS.
3. The agent table's "Needs you" column marks read as text (yes / —), and the row under focus or
   pointer gets the recorder's pen-red edge.

## Page order

1. Skip link, small header: app icon (from `assets/brand/icon.png`), "Agent Awake".
2. Hero: h1 "Your Mac stays awake while your agents work." Sub-line. Install block: the brew
   command with copy, "Download 0.1.4 for Mac" to the latest release, "Signed and notarised by
   Apple. macOS 13 or later, on Apple silicon or Intel." Real capture: `setup.png`.
3. One trip in a bag: the strip, its caption, readings table, the four stop rules.
4. What it does.
5. Agents: the list from `Sources/AgentAwakeCore/AgentCatalog.swift` (cited), with each agent's
   signal from README.md 71–90. No count printed. Real capture: `settings-agents.png`.
6. Hooks never block an agent.
7. Pings.
8. Lid closed, in a bag.
9. Source: MIT, build from source.
10. Status, as of the build date: latest release, CI on main, last push, licence. "No data" when
    a value is missing.
11. Footer: maintained date, deploy sha, repo link, hamardikan.com.

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

Left off the page (unresolved, research §8–9): any agent count; the word "free"; competitor
names; download or update-check counts; stars and forks (0).

## Revisions after review

- **Body face:** Source Serif 4 (400, 600), not Literata. It is the face this spec named, it is OFL,
  and its Latin subset is about 20 KB a weight, which keeps the phone first load near 150 KB.
  Literata was never in this build, so there was nothing to switch back from.
- **The four rules** are the lid-closed ones from claim 14: battery 10%, a serious thermal state,
  battery above 41 °C, drain faster than 20% an hour. The 44 °C pause is drawn on the ruler only,
  because no claim explains it.
- **Caption:** see the ruler paragraph above.
- **Strip layout:** the phone chart has its own viewBox (300 wide) with labels at 15 px; the wide
  chart appears from 720 px. Both carry the same numbers and marks.

## Real vs missing

- Real: `assets/screenshots/setup.png`, `assets/screenshots/settings-agents.png`, `assets/brand/icon.png`.
- Missing: a capture of the menu bar panel (the app is not installed on this build Mac and the
  GUI cannot be driven from here); a screen recording; a phone ping capture. Listed for Dika.

## Checklist (PLAYBOOK §8)

Evidence: harness `site/scripts/verify.mjs`, output in
`~/workspace/sandbox/showcase-scan/build/agent-awake/shots/run6/report.md` (local) and
`shots/live/report.md` (live URL). Review rounds: `review-round-*.md` in the same folder.

Copy
- [x] First line says what it is and for whom: h1 "Your Mac stays awake while your agents work."
- [x] Meta and og description name the project in one line (`index.html` head).
- [x] One role list and one contact order: n/a (no contact block; footer links repo and hamardikan.com).
- [x] Denominators in the intro: n/a (no team or user numbers on the page).
- [x] No ⚠️, [confirm], TBD, XX: harness text check PASS.
- [x] Voice: read aloud; British spelling (notarised, licence, behaviour), no Oxford comma, no
  exclamation marks, no marketing words, no "free", no agent count, no competitor names.
- [x] Every claim row OK (claims table above; claims 9 and 16 corrected after review round 1).

Claims and data
- [x] Units and windows: 75 minutes, 100% → 59%, 32.8% an hour with its arithmetic, 41/44 °C with
  the author's two-day log and the half-hour bag window.
- [x] Live numbers dated: Status block and hero cask line carry the build date.
- [x] No placeholders, no empty sections; missing captures are listed below, not framed in grey.

Accessibility and phone
- [x] Skip link first and works; one h1; `lang="en-GB"`: harness PASS.
- [x] Contrast: lowest text pair 5.72:1 (dark, thermal band text), UI 4.10:1; axe zero violations
  at 1440 and 375, light and dark.
- [x] Zero console errors, zero failed or third-party requests: harness PASS.
- [x] No horizontal scroll at 320, 375, 820, 1440: harness PASS (360 sits between 320 and 375).
- [x] Touch copy: "Select a rule"; no hover-only reveal (rules are buttons, tap pins a rule).
- [x] Things to press before the first scroll on a phone: Copy and Download.
- [x] Reduced motion: no animations after load (harness); strip is static. No loop on the page.
- [x] JS off: strip and readings table visible; Copy button stays hidden (harness).
- [x] SVG labels render ≥14 px at 320 (harness computes font-size × scale).

Visuals
- [x] One signature object from a real artifact (CHANGELOG 0.1.2), static in markup.
- [x] Banned list: no gradients (the only one is inside Apple's own setup window capture), no
  cards, no pills, no fake terminal (the brew line is a plain code block with a Copy button), no
  icon soup, no fade-ups.

Privacy
- [x] No IPs, hostnames other than public ones, account or zone IDs, secret or binding names in
  page, source comments or images (grep of `dist/` and `wrangler.jsonc`).
- [x] No "ADI", no CV link, no private split.

Deploy
- [x] Root-absolute URLs for internal links and assets.
- [x] No `_redirects`; nothing shadows a page.
- [x] CSP `default-src 'self'`, no inline script or style, `form-action 'none'`,
  `frame-ancestors 'none'`, `base-uri 'none'`.
- [x] `/assets/*` immutable, file names fingerprinted by `build.sh`.
- [x] Hero does not move after load (image width/height set; strip height reserved).
- [x] Live copy checked after deploy (see REPORT.md).

## Self-critique

*Would a design-literate engineer guess this was AI-generated? Why not?*

Mostly not. The page has one idea and follows it: a recorder printout of a real trip, with the two
readings drawn as dots and the missing middle drawn as a dashed chord that says it was not recorded.
Generated pages invent a smooth curve there; this one refuses to. The type is a reading serif with a
mono scale, on paper, with one pen red and one pen blue; there are no cards, chips, glows or stock
icons, and the only images are the app's own windows.

What still smelled, and what was done:
- The first build crowded labels on the chart and let the brew command break at a hyphen; both fixed.
- "Hooks never block an agent" repeated the README's line, which the code contradicts (the heat
  gate waits up to ten minutes); rewritten as "Hooks stay out of the way" with the wait stated.
- Bare file-name citations read like an internal report; they now link to the pinned lines.
- Still there: the "ch n" section labels, which a reviewer called repetitive. Kept, because they are
  the recorder-roll edge the concept rests on, set small and hidden from screen readers.
- Still there: the hero capture is Apple's setup window, which has a blue gradient of its own. It is
  a real capture, so it stays; a menu bar capture would be better (open question for Dika).
