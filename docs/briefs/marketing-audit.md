# Marketing audit: Agent Awake

Read-only. Sources: repo at `c56c4e0` (branch `marketing-audit`); live page parsed as HTML (footer: deploy `c56c4e0`, built 25 Nov 2026); `gh` reads and the cask file on 2026-11-28; comparables read from public pages the same day.

## First five seconds

| Surface | Verdict | Evidence |
|---|---|---|
| README | Says what it does in two lines; no picture of the product in use; install below the fold | Tagline lines 5-6 ("caffeinate for AI agents."). Download link line 15. Two screenshots lines 17-18: setup window and Settings. `brew install` line 53. "menu bar" first appears line 61. No GIF or video in `assets/`. |
| Site | Clean and specific, but the body never says it is a menu bar app, and the hero has no install line | H1 line 89, lede line 90, one button line 91 (live: "Download 0.1.4 for Mac"). Visible body has no "menu bar" (only head and JSON-LD, lines 7, 12, 21, 46). `brew install` at line 368 of 409. Signing and notarisation only at line 365. |
| GitHub page | Accurate description with a stale agent count; no custom image; 0 stars | Description: "Cursor and 15 more agents" (= 18). `usesCustomOpenGraphImage: false`. 11 topics. Homepage set to the site. |
| Cask | Version and desc correct; homepage and caveats missing | `version "0.1.4"` = latest release. `desc` "Stay awake while AI coding agents work, then sleep and ping your phone". `homepage` = repo, not the site. No `caveats`. |

Overall: the real differences (phone pings when away, state reported by each agent's own hooks, heat and memory waiting, lid-closed with stop rules, signed and notarised) are in the README and site body. None of the four first screens leads with them. They lead with "keep your Mac awake while agents work", which the comparables also lead with.

## Comparables

| Product | First-screen pitch | Shows on first screen | Trust | Install | FAQ |
|---|---|---|---|---|---|
| Let It Brew (letitbrew.app) | "Close the lid. Let it brew." Meta: "Free, open-source menu-bar app that keeps your Mac awake while Claude Code, Codex, ... works" | Product-like mock of its menu with agent states; "Works with nine agents today" with logos | Line under button: "Free · macOS 14+ · Apple silicon & Intel". "No account, cloud service, or telemetry. Session data stays on your Mac." | Download and "Star on GitHub"; no brew line in reader text | None seen; compare pages ("vs Caffeine and Amphetamine") |
| Afterhours (github.com/PunGrumpy/afterhours) | "Your agents work after hours, this keeps your Mac awake for them." | Names 21 agents in the second paragraph | States the app is not notarised yet, with the Open Anyway step | DMG and `brew install --cask` | Numbered install steps |
| Insomnia (github.com/phin/insomnia) | "Keep your Mac awake while an AI coding agent is working." | Hero image and menu screenshot | "No API keys, no telemetry, nothing to configure. Open source under the MIT license." | Not in the part read | Disambiguation note about a same-named API client |
| Barista (github.com/cb-117/barista) | "Keeps your Mac awake while the work brews. A free, open-source Mac menu-bar app ..." | Real menu bar and panel screenshots, light and dark | "free, open-source" | Not in the part read | Website and CHANGELOG |
| KeepingYouAwake (github.com/newmarcel/KeepingYouAwake) | "a small menu bar utility for macOS" | Nothing above the fold | "Is this dangerous?" answered plainly | `brew install --cask` line | Questions as headings: "Does it work on a MacBook with a closed lid? No." |
| Amphetamine (App Store id937984704) | "the most awesome keep-awake app ever created for macOS" | Store screenshots (not read) | Store review; price 0; macOS 10.13+ | Store button | Store description bullets |
| Raycast "Coffee" (raycast.com/mooxl/coffee) | "Keep your computer awake ... with menu bar status. Like caffeinate." | Store listing | Install count shown (164,730 in the search snippet) | Raycast install | None |

What the comparables do that the Agent Awake site does not:
- Show the product on the first screen (Let It Brew mock, Barista screenshots). Agent Awake's only images are a painting and, below the fold, a Settings capture.
- Put a platform or trust line under the download button (Let It Brew).
- State privacy in one line (Let It Brew, Insomnia). Agent Awake has the facts (change 13) but no line.
- Ask the lid-closed and safety questions as questions (KeepingYouAwake). Agent Awake answers them only in prose (site lines 157-158).

Crowding: at least six other open-source or free apps do this job (the five above plus Keepresso and Wakey, seen in search results only). "Only" or "first" claims are not supportable yet (missing evidence 6).

## Ranked changes (most impact for least effort first)

Each: what / where / why / evidence / effort / owner.

1. **Hero: one-line install and trust line under the button.**
   - What: under the button add "Signed with Developer ID and notarized by Apple · macOS 13 or later · `brew install --cask hmrdkn-labs/tap/agent-awake`". Keep the Install section.
   - Where: `site/src/index.html` lines 86-93 (button line 91). Source sentences at lines 365 and 368.
   - Why: the five-second test needs an install line on the first screen. The only one is line 368 of 409.
   - Evidence: live hero has only "Download 0.1.4 for Mac". Let It Brew puts its platform line under its button.
   - Rules: both sentences have claim rows (NOTES.md rows 19 and 21). No rule change.
   - Effort: S. Owner: deploy (`npm run deploy` needs the Worker's Cloudflare token).

2. **Record the real product: menu bar panel, a phone ping, a screen recording.**
   - What: three captures from the real app and a real phone: (a) menu bar panel while two agents work; (b) the ping on the phone; (c) 20-30 s screen recording: agent starts, lid stays open, agent ends, Mac may sleep. Put (a) or (c) in the README above Install, as the second visual on the site, and as the social preview (change 5).
   - Where: new files in `assets/screenshots/`; README after line 18; `site/src/index.html` section 2 after line 99.
   - Why: a menu bar app is invisible in static shots. The two existing images are a setup window and Settings. The comparables show the panel (Let It Brew, Barista).
   - Evidence: `assets/` holds only `brand/` and two `screenshots/` files. NOTES.md lines 82-83 list the three missing captures.
   - Rules: real captures only (NOTES.md line 26, "real captures stay real"). No mocks.
   - Effort: M. Owner: yes. Needs the owner's Mac and phone.

3. **Say "menu bar app" in the visible copy.**
   - What: site lede or line under the h1, e.g. "A menu bar app for macOS. It keeps your Mac awake while AI agents work, then lets it sleep and pings your phone if you are away." README: add the same fact to the opening paragraph (line 22).
   - Where: `site/src/index.html` line 90; `README.md` line 22.
   - Why: the body never names the product form. The head says "Open-source menu bar app" (lines 7, 12, 21, 46); a reader of the body does not see it.
   - Evidence: `rg "menu bar" site/src/index.html` hits only the head and JSON-LD. README line 61 is the first mention.
   - Rules: add a claim row citing README.md line 61.
   - Effort: S. Owner: copy approval; deploy.

4. **Label the four paintings as illustrations.**
   - What: a visible "Illustration" caption, or alt text starting "Illustration:", on the hero, bag, phone and closing images.
   - Where: `site/src/index.html` lines 87, 163, 350, 387.
   - Why: the hero alt text describes a real scene ("Its screen gives off a soft amber glow"). A visitor cannot tell the painting from a photo of the product. This is the one place the page implies a product look it does not have.
   - Evidence: live HTML has 0 matches for "illustration". NOTES.md lines 82-83: "Generated images are illustration only."
   - Effort: S. Owner: no; deploy.

5. **Set a GitHub social preview.**
   - What: upload `site/src/og.jpg` (1200x630, meta at site lines 16-17) under repo Settings → Social preview. Swap in a real capture once change 2 exists.
   - Why: GitHub shows a generated card when no image is set, so shared links show a generic card.
   - Evidence: `gh repo view` gives `usesCustomOpenGraphImage: false`; `openGraphImageUrl` is the generated `opengraph.githubassets.com` card.
   - Effort: S. Owner: yes (repo settings).

6. **Fix the count and the one-liner in the GitHub description.**
   - What: drop the count: "caffeinate for AI agents: keeps your Mac awake while coding agents work, sleeps when they finish, and pings your phone."
   - Why: the count disagrees across surfaces. GitHub says 18 ("Cursor and 15 more"). The README table has 18 rows (oh-my-pi and pi share one). `AgentCatalog.swift` has 19 `AgentSpec(id:` entries. CHANGELOG 0.1.0 says 19. The site list has 19 items.
   - Evidence: `gh repo view` description; `rg -c "AgentSpec\(id:" Sources/AgentAwakeCore/AgentCatalog.swift` = 19.
   - Effort: S. Owner: yes (repo settings).

7. **Link SECURITY.md where the root helper is explained.**
   - What: link under "Lid-closed mode" (README lines 153-170) and in the site lid section (line 157). Text: "What the helper can and cannot do: SECURITY.md."
   - Why: SECURITY.md is the only plain statement of what runs as root: one XPC call, from clients with the app's Team ID and bundle ID, restores sleep when the lease ends. Neither README nor site links it. Lid-closed is the feature a visitor should worry about.
   - Evidence: `rg SECURITY README.md site/src/index.html` gives no hits. SECURITY.md lines 14-16.
   - Rules: claim row for the link, pinned blob URL (NOTES.md row 28 pattern).
   - Effort: S. Owner: no; deploy.

8. **Cask: homepage to the site, add caveats.**
   - What: `homepage "https://agentawake.hamardikan.com/"`; add `caveats` "Lid-closed mode needs one approval in System Settings → Login Items." Keep `desc` (it is the best one-liner in the set) or align it with change 6.
   - Where: `hmrdkn-labs/homebrew-tap`, `Casks/agent-awake.rb`.
   - Why: `brew info` shows the homepage. Caveats print after install, where the Login Items approval (README lines 158-159) would otherwise come with no explanation.
   - Evidence: cask file has no `caveats`; `homepage` is the repo.
   - Effort: S. Owner: yes (push to the tap repo, outside this repo).

9. **Add two GitHub topics.**
   - What: add `keep-awake` and `coding-agents`. Keep the existing 11 (`ai-agents`, `caffeinate`, `claude-code`, `codex`, `cursor`, `developer-tools`, `macos`, `menubar-app`, `notifications`, `swift`, `swiftui`).
   - Why: `keep-awake` is the phrase users search for; it is absent. [INFERENCE: search reach not measured.]
   - Effort: S. Owner: yes (repo settings).

10. **Lead with the differentiators in the first two lines.**
    - What: hero lede and README line 22 put what is different first: "Agents tell it when they start, finish and need you. Your Mac stays awake only while they work, and your phone pings when you are away."
    - Why: the five comparable first screens say "keeps your Mac awake while agents work" in nearly the same words. Phone pings are not in Let It Brew's feature list.
    - Evidence: README lines 26-27 and 30-32; site line 90; comparables table.
    - Rules: maps to claim rows 1, 2, 6 and 9. No new rows.
    - Effort: S. Owner: copy approval. Do not write "only" or "first" until missing evidence 6 is done.

11. **Release notes 0.1.4 read as a stub.**
    - What: the release body is four lines about the updater and brew. Add three or four lines from CHANGELOG.md 10-22 (agent waiting, heat and memory, lid-closed stop rules) and link the site.
    - Why: the Download button lands on this page, and returning users check what changed here.
    - Evidence: `gh release view` body; CHANGELOG.md 10-22 has the text.
    - Effort: S. Owner: yes (publishes under the owner's account).

12. **FAQ: battery, privacy, lid, agents, removal.**
    - What: six questions, each answer with a claim row:
      - Does it drain the battery? Only while agents run. The recorded bag trip, lid closed, drained 41% in 75 min (CHANGELOG.md 26-27). Stop rules: 10%, 41 °C, serious thermal state, 20% an hour. Show the number.
      - Does it send my prompts anywhere? Pings name only the agent and folder by default (README 119-120). Network: ping channels you set up, and GitHub for updates (`Resources/Info.plist` line 16, `SUFeedURL`). Publish only after missing evidence 7.
      - Does it work with the lid closed? Yes, optional, off by default. One approval in Login Items. Stops at 10% battery (README 153-170).
      - Which agents? Link to the table (README 71-90). Connect in Settings → Agents, or `agentawake connect <id>`.
      - Why approve a helper? It runs as root only to switch `pmset disablesleep` (SECURITY.md 14-16).
      - How do I remove it? Disconnect removes what Connect added (README 66-67). The helper removal path is not documented (missing evidence 10).
    - Why: KeepingYouAwake answers the closed-lid and "dangerous" questions directly. Agent Awake's answers exist as prose (site lines 157-158), not as the questions a visitor asks.
    - Effort: M. Owner: none; each answer needs a claim row.

13. **Privacy line.**
    - What: "Nothing goes to us. Pings go only to the channels you set up, and updates are checked on GitHub." Publish after missing evidence 7 is done.
    - Evidence: README 119-122. Static search of `Sources`, `scripts` and `Resources` finds no analytics, telemetry, StoreKit or purchase code. Network endpoints are the ping channels in `Sources/AgentAwakeCore/Channels/` and the GitHub appcast (`Resources/Info.plist:16`).
    - Effort: S after evidence. Owner: wording approval.

14. **US spelling on the site.**
    - What: "Licence" (live status row, site line 379), "notarised" (site line 365; README uses "notarized") to US "License" and "notarized". Matches the README, cask, release notes and US search terms.
    - Why: one product, two spellings across surfaces. `<html lang="en-GB">` (line 2) may be deliberate; the owner decides.
    - Effort: S. Owner: yes (en-GB may be a choice).

15. **Submit sitemap and IndexNow key.**
    - What: NOTES.md "Search (v3)" says the IndexNow key sits at the root and is not submitted; the sitemap is written by the build. Submit both.
    - Why: search is the one acquisition channel that costs nothing, and the page already carries the query.
    - Effort: S. Owner: yes (search accounts).

## Rule changes (owner decides; not assumed)

- **R1. "No agent count"** (site/README.md line 38; NOTES.md line 118). The 19-item list is on the page (site lines 113-136), so the count is visible but unstated. Proposal: a count generated from `AgentCatalog.swift`, with a build check that README and site lists agree. Trade-off: fix the definition first (19 ids vs 18 README rows). Competitors lead with counts ("nine agents", "21 agents").
- **R2. "No 'free'"** (site/README.md line 38; NOTES.md line 118). The app itself is free: MIT (NOTES.md claim 23), and a search of `Sources`, `scripts` and `Resources` for StoreKit, purchase, license-key and paywall code finds nothing. Paid pieces exist only in third-party channels (Pushover "one-time $5", README line 115). Proposal: "Free and open source (MIT)". Let It Brew and Barista use "free" in their first line.
- **R3. "No competitor names"**. Keep on the homepage. A comparison page is a separate decision. Let It Brew runs `/compare/...` pages. Not recommended until missing evidence 6 is done.
- **R4. Lid-closed heading.** "Sleep safeguards with the lid closed" (site line 155) is defensive, and NOTES.md M4 chose it on purpose. A bolder heading is fine if "optional, off by default" stays in the same paragraph. This is copy, not a rule.

## Missing evidence

1. Real captures: menu bar panel, phone ping, screen recording (NOTES.md 82-83). Owner records.
2. Clean-machine install (NOTES.md claim 21, "open question"): fresh macOS user, `brew install --cask`, first launch.
3. Intel: `scripts/bundle.sh:17` builds `arm64` and `x86_64`; README line 56 says "Apple silicon or Intel". No Intel run is recorded in the repo.
4. Battery with the lid open during an agent hour. The only number is a lid-closed bag trip (CHANGELOG.md 26-27). Needs a measured run with the method written down.
5. Heat limits from one machine: MacBook Pro M4 Pro, two days (README 138-139). Say so wherever the limits appear.
6. Competitive claims: no feature matrix. I read the first screens of five comparables and Amphetamine's store metadata. Any "only", "first" or "unlike others" needs each competitor's README or site read.
7. Privacy negative claim ("nothing goes to us"): needs a runtime network capture during a session with each channel on. Only a static search has been done.
8. Security: no independent review of the root helper. SECURITY.md is self-description. Do not write "audited".
9. Social proof: 0 stars (`stargazerCount` 0), 5 releases since 2026-10-11, no user quotes. Honest route: ask five real users for permission to quote. Do not invent.
10. Helper removal: `Sources/AgentAwakeApp/Helper.swift:41` has an `unregister()` call. The README, site and cask do not say how a user removes the helper after dragging the app to the Trash. Check the UI path before the FAQ answers it.

## Not read or partial

- Amphetamine: store description and price from JSON-LD only; no screenshots or reviews.
- Let It Brew: landing page reader text only; compare pages and any FAQ not opened.
- Afterhours, Barista, Insomnia: README top only.
- Raycast Coffee: search snippet, not the full listing.
- Keepresso, Wakey, one comparison article: search snippets only.
- Site: parsed HTML, not rendered in a browser. Chart SVG (lines 170-317) read, not visually checked.
- Live status rows: CI value not extracted from the HTML.
- `brew install` on a clean machine: not run (read-only brief).

## Report
