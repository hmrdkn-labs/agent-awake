# Agent Awake site

The landing page for Agent Awake, at https://agentawake.hamardikan.com/. Plain HTML and CSS with two small scripts (`strip.js`, `copy.js`). No framework, no bundler, no third-party requests, no analytics. Served by a Cloudflare Worker with static assets only (`wrangler.jsonc`, no `main`).

`NOTES.md` is the spec: concept, the bag-trip strip, page order and the claims table. Every sentence on the page maps to a row in that table.

## Layout

- `src/index.html`, `src/404.html`: the pages. `{{PLACEHOLDERS}}` in `index.html` are filled at build time.
- `src/style.css`, `src/strip.js`, `src/copy.js`: styles and scripts.
- `src/assets/`: fonts (Source Serif 4 and IBM Plex Mono, Latin subset, with their OFL licences in `fonts/`), and webp captures cut from `assets/screenshots/` and `assets/brand/icon.png` in the repo root.
- `src/_headers`, `src/robots.txt`, `src/favicon.svg`, `src/apple-touch-icon.png`, `src/og.png`.
- `scripts/build.sh`: builds `dist/`.

## Build

```sh
npm install        # wrangler only
npm run build      # bash scripts/build.sh -> dist/
```

The build needs an authenticated `gh`. It makes read-only calls for the latest release, CI on `main`, last push, licence and the Homebrew cask version, and stamps them into the status section with the build date (UTC) and the short git sha. A value it cannot read shows as "No data". The build fails when the cask version differs from the release tag, because the page prints both the brew command and the release.

Everything under `assets/`, plus the stylesheet and scripts, gets an eight-character content hash in its name, and the references are rewritten. `_headers` caches `/assets/*` as immutable on that basis. `dist/` is built in a temporary directory and moved into place.

To look at it: `python3 -m http.server -d dist <free port>`. The python server does not apply `_headers`.

## Deploy

```sh
npm run deploy     # builds, then wrangler deploy
```

Run it with the Cloudflare token for this Worker only. No account or zone IDs belong in this repo.

## Things to keep true

- No claim without a row in the claims table in `NOTES.md`. No agent count, no "free", no competitor names, no star or download counts.
- The strip draws only the two recorded readings and the dashed line between them. Never a battery curve.
- The strip is fully drawn in the markup. JS only adds the one-time chord animation, and only when `prefers-reduced-motion: no-preference`.
- CSP stays strict: no inline script or style, no third-party origins.
- Phone first load stays under 300 KB.
- Colour pairs stay at 4.5:1 for text and 3:1 for UI and focus, in light and dark.
- If the agent list changes in `Sources/AgentAwakeCore/AgentCatalog.swift` or the README table, update the agents table in `src/index.html`.
