# Launch captures (owner)

Record these on your Mac and phone. Real captures only, no mock-ups or generated images
(`docs/briefs/marketing-audit.md`, change 2). Put every file in `assets/screenshots/`.

| # | File | Format | Goes where |
|---|---|---|---|
| 1 | `menu-panel.png` | PNG, screenshot | site section 2; social preview option |
| 2 | `phone-ping.png` | PNG, screenshot | site section 2, if you want it there (the audit does not place it) |
| 3 | `demo.mp4` and `demo.webm` | MP4 and WebM, same 20-30 s recording | site section 2 |
| 4 | `demo.gif` | GIF, 3 MB or less, cut from #3 | README, at the `demo:` comment under the screenshots |
| 5 | `social-preview.png` | PNG, 1280x640 | repo Settings → Social preview (audit change 5) |

## 1. Menu bar panel, two agents working

1. Settings → Agents: connect Claude Code and Codex (README, "Supported agents").
2. Submit a prompt in each, so both are working. A prompt submitted is what starts work
   (`Sources/AgentAwakeCore/AgentCatalog.swift:5`).
3. Click the moon in the menu bar (README, "Install": "lives in the menu bar as a moon").
4. Capture the panel with both sessions listed as running (CHANGELOG 0.1.0: the panel shows
   "what's running"). Crop to the menu bar and the panel.

## 2. Phone ping

- Channel: ntfy, the channel set up on first run (README, "Pings" table). Name the channel in
  the caption if you use another one from that table.
- Default text: `Claude Code · <folder> is done`. The README example is "Claude Code · shop is
  done" (README, "Pings"). Pings name only the agent and project folder; task titles are opt-in
  (README, "Pings"; CHANGELOG 0.1.0). Keep the opt-in off for this capture.
- The default wording of needs-you and error pings is not written in the repo. Record the exact
  text you see.

Steps:

1. Phone: subscribe to the ntfy topic Agent Awake uses (set on first run; README, "Pings").
2. Mac: Settings → Notifications → "when away" (README, "Pings": when away, always, never).
3. Lock the Mac or leave it idle. Pings go to the phone only while you are away from the Mac
   (README, feature list, "Pings that matter").
4. Run a short Claude Code task in a project folder with a short name, and let it finish.
5. Capture the notification on the phone with its text readable.

## 3. Screen recording, 20-30 s

Setup: lid open, Agent Awake running, Claude Code connected (Settings → Agents), a short prompt
ready. The frame shows the menu bar and the terminal.

| Time | Action | The clip must show |
|---|---|---|
| 0-4 s | Nothing running | Empty menu bar panel |
| 4-8 s | Submit the prompt in Claude Code | The panel lists the session |
| 8-18 s | Leave the lid open while the agent works | Nothing touched; work keeps the Mac awake (README, feature list, "Awake only while agents work") |
| 18-24 s | Agent finishes | The session leaves the panel; the done ping goes out (`AgentCatalog.swift:8`, `stop`: the turn finished) |
| 24-30 s | Stop recording | |

Rules:

- Real time, no mock-up. If the agent finishes early, use a longer task so the clip stays 20-30 s.
- Do not caption a sleep moment. The clip ends before any sleep, and the repo sets no sleep time:
  normal sleep comes back by itself after the last session (README, feature list).

## Formats and placement

- README GIF: `assets/screenshots/demo.gif`, 3 MB or less. Check the size after export; if it is
  over, shorten the clip or reduce its size.
- Site video: `assets/screenshots/demo.mp4` and `demo.webm`, from the same recording.
- Social preview: `assets/screenshots/social-preview.png`, 1280x640 PNG. Upload it under repo
  Settings → Social preview. It replaces GitHub's generated card. Use a real capture (#1, or a
  crop of #3).

## Missing evidence checklist

From `docs/briefs/marketing-audit.md`, "Missing evidence". Tick each when it is done.

- [ ] 1. Real captures: menu bar panel, phone ping, screen recording (this file, #1-#3).
- [ ] 2. Clean-machine install: fresh macOS user, `brew install --cask hmrdkn-labs/tap/agent-awake`, first launch.
- [ ] 3. Intel run: `scripts/bundle.sh` builds x86_64, and no Intel run is recorded. README says "Apple silicon or Intel".
- [ ] 4. Battery with the lid open during an agent hour, with the method written down. The only number today is the lid-closed bag trip (CHANGELOG 0.1.2).
- [ ] 5. Heat limits come from one machine (MacBook Pro M4 Pro, two days). Say so wherever the limits appear (README, "Heat and memory").
- [ ] 6. Competitive claims: a feature matrix from each competitor's README or site before any "only", "first" or "unlike others".
- [ ] 7. "Nothing goes to us": a runtime network capture with each ping channel on. Only a static search has been done.
- [ ] 8. Independent review of the root helper. SECURITY.md is self-description. Do not write "audited".
- [ ] 9. Social proof: ask five real users for permission to quote them. Do not invent quotes.
- [ ] 10. Helper removal: check the UI path (`Sources/AgentAwakeApp/Helper.swift:41` calls `unregister()`), then document how a user removes the helper after moving the app to the Trash.
