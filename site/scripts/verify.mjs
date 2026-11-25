#!/usr/bin/env node
// Verification harness for the Agent Awake landing page.
// Usage: NODE_PATH=~/.cache/agent-awake-pw/node_modules node site/scripts/verify.mjs <dist-dir | base-url> <out-dir>
// A directory is served here on a free port bound to 127.0.0.1. Either way the page must contain "Agent Awake" before any check runs.
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, renameSync, mkdtempSync, rmSync, statSync, existsSync } from 'node:fs';
import { createServer } from 'node:net';
import { join, resolve } from 'node:path';
import { homedir, tmpdir } from 'node:os';

const [baseArg, outArg] = process.argv.slice(2);
if (!baseArg || !outArg) {
  console.error('usage: node verify.mjs <base-url> <out-dir>');
  process.exit(2);
}
let server = null;
const freePort = () => new Promise((res, rej) => {
  const s = createServer();
  s.once('error', rej);
  s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => res(port)); });
});
let BASE;
if (existsSync(baseArg) && statSync(baseArg).isDirectory()) {
  const port = await freePort();
  server = spawn('python3', ['-m', 'http.server', String(port), '-b', '127.0.0.1', '-d', resolve(baseArg)], { stdio: 'ignore' });
  BASE = new URL(`http://127.0.0.1:${port}/`);
} else {
  BASE = new URL(baseArg);
}
process.on('exit', () => { try { server?.kill('SIGKILL'); } catch {} });
let pageOk = false;
for (let i = 0; i < 25 && !pageOk; i++) {
  try { pageOk = (await (await fetch(BASE.href)).text()).includes('Agent Awake'); } catch {}
  if (!pageOk) await new Promise((r) => setTimeout(r, 200));
}
if (!pageOk) {
  console.error(`${BASE.href} did not answer with a page containing "Agent Awake"; refusing to run checks.`);
  process.exit(2);
}
const OUT = resolve(outArg);
mkdirSync(OUT, { recursive: true });

const NM = (process.env.NODE_PATH || '').split(':').filter(Boolean)[0] ||
  join(homedir(), '.cache/agent-awake-pw/node_modules');
const req = createRequire(join(NM, 'noop.js'));
const { chromium } = req('playwright');
const { AxeBuilder } = req('@axe-core/playwright');

const results = []; // {name, pass, detail}
const extra = {};
const record = (name, pass, detail = '') => {
  results.push({ name, pass: !!pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}${detail ? ' :: ' + String(detail).split('\n')[0].slice(0, 200) : ''}`);
};

const SIZES = {
  d: { width: 1440, height: 900 },
  m: { width: 375, height: 812 },
  s: { width: 320, height: 700 },
  t: { width: 820, height: 1180 },
};
const STRIP = '.strip-fig svg';

async function scrollStrip(page) {
  await page.evaluate(async (sel) => {
    await document.fonts.ready;
    const el = document.querySelector('#strip .strip-fig') || document.querySelector('.strip-fig');
    if (el) el.scrollIntoView({ block: 'center' });
  }, STRIP).catch(() => {});
}

async function newCtx(browser, opts = {}) {
  const { size = 'd', ...rest } = opts;
  return browser.newContext({ viewport: SIZES[size], deviceScaleFactor: 1, ...rest });
}

async function loadPage(ctx) {
  const page = await ctx.newPage();
  await page.goto(BASE.href, { waitUntil: 'load' });
  return page;
}

// Visible-text sampling run in page.
const measure = () => {
  const vis = (el) => {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none' && +cs.opacity !== 0;
  };
  const out = { minFont: null, fonts: [], paragraphs: [], targets: [] };
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n;
  const seen = new Set();
  while ((n = walker.nextNode())) {
    if (!n.nodeValue.trim()) continue;
    const el = n.parentElement;
    if (!el || seen.has(el) || ['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(el.tagName)) continue;
    // hidden via ancestor?
    let hidden = false;
    for (let a = el; a; a = a.parentElement) {
      const cs = getComputedStyle(a);
      if (cs.display === 'none' || cs.visibility === 'hidden') { hidden = true; break; }
    }
    if (hidden) continue;
    const r = el.getBoundingClientRect();
    if (!r.width || !r.height) continue;
    // clip-hidden (sr-only) text
    if (r.width <= 1 || r.height <= 1) continue;
    seen.add(el);
    let px = parseFloat(getComputedStyle(el).fontSize);
    if (el instanceof SVGElement && el.getScreenCTM) {
      const m = el.getScreenCTM();
      if (m) px *= Math.hypot(m.a, m.b);
    }
    out.fonts.push({ px: +px.toFixed(2), tag: el.tagName.toLowerCase(), text: n.nodeValue.trim().slice(0, 40) });
  }
  out.fonts.sort((a, b) => a.px - b.px);
  out.minFont = out.fonts[0] || null;
  // body copy only: the .prose paragraphs and the lede. Small print (.small, .fine, .cap), tables and the footer are covered by the 14px floor.
  for (const p of document.querySelectorAll('p.prose:not(.small), .prose:not(.small) p, .lede')) {
    if (p.textContent.trim().length < 20 || !vis(p)) continue;
    out.paragraphs.push({ px: parseFloat(getComputedStyle(p).fontSize), text: p.textContent.trim().slice(0, 40) });
  }
  const sel = 'a[href], button, input, select, textarea, summary, [role=button], [role=link], [tabindex]:not([tabindex="-1"])';
  for (const el of document.querySelectorAll(sel)) {
    if (!vis(el)) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 1 || r.height <= 1) continue;
    const inline = el.tagName === 'A' && getComputedStyle(el).display === 'inline' && el.closest('p, li, figcaption, dd');
    if (inline) continue;
    if (r.width < 43.5 || r.height < 43.5) {
      out.targets.push({
        tag: el.tagName.toLowerCase(),
        text: (el.innerText || el.getAttribute('aria-label') || el.id || '').trim().slice(0, 40),
        w: +r.width.toFixed(1),
        h: +r.height.toFixed(1),
      });
    }
  }
  return out;
};

const focusInfo = () => {
  const el = document.activeElement;
  if (!el || el === document.body || el === document.documentElement) return null;
  const cs = getComputedStyle(el);
  const r = el.getBoundingClientRect();
  const outline = cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0 && !/rgba\(\d+,\s*\d+,\s*\d+,\s*0\)|transparent/.test(cs.outlineColor);
  const shadow = cs.boxShadow && cs.boxShadow !== 'none';
  const labelled = el.getAttribute('aria-labelledby');
  let name = el.getAttribute('aria-label') ||
    (labelled && labelled.split(/\s+/).map((i) => document.getElementById(i)?.textContent.trim()).filter(Boolean).join(' ')) ||
    el.getAttribute('alt') ||
    (el.querySelector('title')?.textContent.trim()) ||
    el.innerText?.trim() || el.textContent?.trim() || el.getAttribute('title') || '';
  return {
    tag: el.tagName.toLowerCase(),
    id: el.id || null,
    href: el.getAttribute('href'),
    text: (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60),
    name: name.replace(/\s+/g, ' ').slice(0, 80),
    box: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
    outline: outline ? `${cs.outlineWidth} ${cs.outlineStyle} ${cs.outlineColor}` : null,
    boxShadow: shadow ? cs.boxShadow : null,
    visibleIndicator: !!(outline || shadow),
    key: el.tagName + '|' + (el.id || '') + '|' + (el.getAttribute('href') || '') + '|' + Math.round(r.x) + ',' + Math.round(r.y),
  };
};

async function shots(browser) {
  const runs = [
    ['1440-light', 'd', { colorScheme: 'light' }],
    ['1440-dark', 'd', { colorScheme: 'dark' }],
    ['375-light', 'm', { colorScheme: 'light' }],
    ['375-dark', 'm', { colorScheme: 'dark' }],
    ['320-light', 's', { colorScheme: 'light' }],
    ['820-light', 't', { colorScheme: 'light' }],
    ['1440-reduced', 'd', { colorScheme: 'light', reducedMotion: 'reduce' }],
    ['375-reduced', 'm', { colorScheme: 'light', reducedMotion: 'reduce' }],
    ['1440-nojs', 'd', { colorScheme: 'light', javaScriptEnabled: false }],
    ['375-nojs', 'm', { colorScheme: 'light', javaScriptEnabled: false }],
  ];
  for (const [name, size, opts] of runs) {
    const ctx = await newCtx(browser, { size, ...opts });
    try {
      const page = await loadPage(ctx);
      const reduced = opts.reducedMotion === 'reduce';
      const nojs = opts.javaScriptEnabled === false;
      if (nojs) await page.waitForTimeout(1000);
      else if (reduced) { await page.evaluate(() => document.fonts.ready); await page.waitForTimeout(500); }
      else {
        // play the one-time strip draw first, then go back to the top, so every shot shows the finished strip
        await page.evaluate(() => document.fonts.ready);
        await scrollStrip(page);
        await page.waitForTimeout(3000);
        await page.evaluate(() => window.scrollTo(0, 0));
        await page.waitForTimeout(300);
        if (name === '1440-light' || name === '375-light') await page.screenshot({ path: join(OUT, `first-screen-${name.split('-')[0]}.png`) });
      }
      if (nojs || reduced) {
        if (name.endsWith('light') === false) await page.screenshot({ path: join(OUT, `first-screen-${name}.png`) });
      }
      await page.screenshot({ path: join(OUT, `full-${name}.png`), fullPage: true });
      if (!nojs && !reduced) {
        await page.evaluate(() => window.scrollTo(0, 0));
      }
    } catch (e) {
      record(`screenshot ${name}`, false, e.message);
    } finally {
      await ctx.close();
    }
  }
}

async function demo(browser) {
  const dir = mkdtempSync(join(tmpdir(), 'aa-demo-'));
  const ctx = await browser.newContext({ viewport: SIZES.d, recordVideo: { dir, size: SIZES.d } });
  try {
    const page = await loadPage(ctx);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(800);
    await scrollStrip(page);
    await page.waitForTimeout(4000);
    const inside = () => page.evaluate(() => {
      const strip = document.querySelector('#strip');
      const scope = strip;
      return !!(scope && scope.contains(document.activeElement) && document.activeElement !== scope);
    });
    let entered = false;
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press('Tab');
      const now = await inside();
      if (now) { entered = true; await page.waitForTimeout(1000); }
      else if (entered) break;
    }
    extra.demoFocusedStrip = entered;
    await page.waitForTimeout(500);
  } finally {
    const video = ctx.pages()[0]?.video();
    await ctx.close();
    try {
      if (video) renameSync(await video.path(), join(OUT, 'demo.webm'));
    } catch (e) { record('demo.webm', false, e.message); }
    rmSync(dir, { recursive: true, force: true });
  }
}

async function keyboard(browser) {
  const ctx = await newCtx(browser, { size: 'd', colorScheme: 'light' });
  try {
    const page = await loadPage(ctx);
    await page.evaluate(() => document.fonts.ready);
    const log = [];
    const seen = new Set();
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press('Tab');
      const info = await page.evaluate(focusInfo);
      if (!info) { log.push({ step: i + 1, tag: 'body', note: 'focus left the document' }); break; }
      if (seen.has(info.key)) break;
      seen.add(info.key);
      log.push({ step: i + 1, ...info });
      if (i < 3) await page.screenshot({ path: join(OUT, `focus-${i + 1}.png`) });
    }
    extra.keyboard = log;
    const first = log[0];
    let skipOk = false;
    let skipDetail = 'no focus after first Tab';
    if (first && first.tag === 'a' && first.href && first.href.startsWith('#') && first.href.length > 1) {
      const exists = await page.evaluate((h) => !!document.getElementById(decodeURIComponent(h.slice(1))), first.href);
      skipOk = exists;
      skipDetail = `${first.href} -> ${exists ? 'target exists' : 'MISSING target'} (text "${first.text}")`;
    } else if (first) skipDetail = `first focus is <${first.tag}> "${first.text}" href=${first.href}`;
    record('first Tab lands on skip link with existing target', skipOk, skipDetail);
    const bad = log.filter((l) => l.tag !== 'body' && !l.visibleIndicator);
    record('every focused element has a visible focus indicator (outline/box-shadow)', bad.length === 0 && log.length > 0,
      bad.length ? bad.map((b) => `step ${b.step} <${b.tag}> "${b.text}"`).join('; ') : `${log.length} stops checked`);
    const unnamed = log.filter((l) => l.tag !== 'body' && !l.name);
    record('every focused element has an accessible name', unnamed.length === 0,
      unnamed.map((b) => `step ${b.step} <${b.tag}>`).join('; '));
  } finally {
    await ctx.close();
  }
}

async function axeAndChecks(browser) {
  // axe: light/dark at 1440 and 375
  for (const [scheme, size] of [['light', 'd'], ['dark', 'd'], ['light', 'm'], ['dark', 'm']]) {
    const label = `${SIZES[size].width}-${scheme}`;
    const ctx = await newCtx(browser, { size, colorScheme: scheme });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      await scrollStrip(page);
      await page.waitForTimeout(3000);
      await page.evaluate(() => window.scrollTo(0, 0));
      const r = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa', 'best-practice'])
        .analyze();
      const v = r.violations.map((x) => ({
        id: x.id, impact: x.impact, help: x.help,
        nodes: x.nodes.map((n) => ({ target: n.target.join(' '), summary: n.failureSummary?.split('\n').slice(0, 3).join(' | ') })),
      }));
      extra[`axe-${label}`] = v;
      record(`axe ${label}`, v.length === 0, v.map((x) => `${x.id}(${x.nodes.length})`).join(', '));
    } catch (e) {
      record(`axe ${label}`, false, e.message);
    } finally {
      await ctx.close();
    }
  }

  // Per-size checks: overflow + measure
  for (const size of ['s', 'm', 't', 'd']) {
    const w = SIZES[size].width;
    const ctx = await newCtx(browser, { size, colorScheme: 'light' });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      const o = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, bw: document.body.scrollWidth, iw: window.innerWidth }));
      record(`no horizontal scroll @${w}`, Math.max(o.sw, o.bw) <= o.iw, `scrollWidth ${o.sw}/${o.bw} vs innerWidth ${o.iw}`);
      if (size === 'm' || size === 'd') {
        const m = await page.evaluate(measure);
        extra[`measure-${w}`] = { minFont: m.minFont, smallest5: m.fonts.slice(0, 5), paragraphs: m.paragraphs, targets: m.targets };
        record(`min font-size >=14px @${w}`, m.minFont && m.minFont.px >= 14,
          m.minFont ? `smallest ${m.minFont.px}px <${m.minFont.tag}> "${m.minFont.text}"; ${m.fonts.filter((f) => f.px < 14).length} below 14` : 'no text found');
        const badP = m.paragraphs.filter((p) => p.px < 17 || p.px > 22);
        record(`body copy 17-22px (.prose p, .lede); all other text >=14px @${w}`, m.paragraphs.length > 0 && badP.length === 0,
          m.paragraphs.length ? (badP.length ? badP.map((p) => `${p.px}px "${p.text}"`).join('; ') : `${m.paragraphs.length} paragraphs, ${[...new Set(m.paragraphs.map((p) => p.px))].join('/')}px`) : 'no paragraphs found');
        record(`interactive targets >=44x44 @${w}`, m.targets.length === 0,
          m.targets.map((t) => `<${t.tag}> "${t.text}" ${t.w}x${t.h}`).join('; '));
      }
    } catch (e) {
      record(`checks @${w}`, false, e.message);
    } finally {
      await ctx.close();
    }
  }

  // Structure + text + console/network at 375 first load (fresh context => cold cache)
  {
    const ctx = await newCtx(browser, { size: 'm', colorScheme: 'light' });
    const page = await ctx.newPage();
    const consoleErrors = [];
    const failed = [];
    const thirdParty = new Set();
    const cdp = await ctx.newCDPSession(page);
    await cdp.send('Network.enable');
    const reqInfo = new Map();
    let bytes = 0;
    const detail = [];
    cdp.on('Network.responseReceived', (e) => reqInfo.set(e.requestId, { url: e.response.url, type: e.type, mime: e.response.mimeType }));
    cdp.on('Network.loadingFinished', (e) => {
      const i = reqInfo.get(e.requestId);
      if (!i) return;
      const media = i.type === 'Media' || /^video\//.test(i.mime || '');
      if (!media) { bytes += e.encodedDataLength; detail.push([i.url.replace(BASE.origin, ''), e.encodedDataLength]); }
    });
    page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
    page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + e.message));
    page.on('request', (r) => {
      const u = new URL(r.url());
      if (u.protocol.startsWith('http') && u.host !== BASE.host) thirdParty.add(u.host);
    });
    page.on('response', (r) => { if (r.status() >= 400) failed.push(`${r.status()} ${r.url()}`); });
    page.on('requestfailed', (r) => failed.push(`failed ${r.url()} ${r.failure()?.errorText}`));
    try {
      await page.goto(BASE.href, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(500);
      const s = await page.evaluate(() => ({
        h1: document.querySelectorAll('h1').length,
        lang: document.documentElement.getAttribute('lang'),
        main: !!document.querySelector('main'),
        text: document.body.innerText,
      }));
      record('exactly one h1', s.h1 === 1, `${s.h1} found`);
      record('html[lang] set', !!s.lang, s.lang || 'missing');
      record('main exists', s.main);
      record('zero console errors', consoleErrors.length === 0, consoleErrors.join(' | '));
      record('zero failed requests (>=400 / requestfailed)', failed.length === 0, failed.join(' | '));
      record('zero third-party requests', thirdParty.size === 0, [...thirdParty].join(', '));
      const kb = bytes / 1024;
      extra.transfer = { kb: +kb.toFixed(1), files: detail.sort((a, b) => b[1] - a[1]).slice(0, 12) };
      record('first-load transfer @375 < 300 KB (excl. video)', kb < 300, `${kb.toFixed(1)} KB; largest: ${detail.sort((a, b) => b[1] - a[1]).slice(0, 3).map((d) => `${d[0]} ${(d[1] / 1024).toFixed(1)}KB`).join(', ')}`);
      const bannedRes = [
        ['{{', /\{\{/], ['TODO', /\bTODO\b/], ['TBD', /\bTBD\b/], ['XX', /\bXX+\b/], ['free', /\bfree\b/i],
        ['IPv4-shaped string', /\b\d{1,3}(?:\.\d{1,3}){3}\b/],
      ];
      const hits = bannedRes.filter(([, re]) => re.test(s.text)).map(([n, re]) => `${n}: "${(s.text.match(re) || [''])[0]}"`);
      record('page text has no {{, TODO, TBD, XX, free, IPv4', hits.length === 0, hits.join('; '));
    } catch (e) {
      record('first-load checks @375', false, e.message);
    } finally {
      await ctx.close();
    }
  }

  // JS off
  for (const size of ['d', 'm']) {
    const w = SIZES[size].width;
    const ctx = await newCtx(browser, { size, javaScriptEnabled: false });
    try {
      const page = await loadPage(ctx);
      await page.waitForTimeout(500);
      const table = page.locator('table').first();
      const sv = await page.evaluate(() => [...document.querySelectorAll('.strip-fig svg')].some((s) => {
        const r = s.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && getComputedStyle(s).display !== 'none';
      }));
      const tv = (await table.count()) > 0 && (await table.isVisible());
      record(`JS off @${w}: strip SVG and readings table visible`, sv && tv, `strip ${sv}, table ${tv}`);
    } catch (e) {
      record(`JS off @${w}`, false, e.message);
    } finally {
      await ctx.close();
    }
  }

  // Reduced motion
  for (const size of ['d', 'm']) {
    const w = SIZES[size].width;
    const ctx = await newCtx(browser, { size, reducedMotion: 'reduce' });
    try {
      const page = await loadPage(ctx);
      await page.waitForTimeout(2000);
      const a = await page.evaluate(() => document.getAnimations().map((x) => `${x.constructor.name}:${x.animationName || x.transitionProperty || x.id}:${x.effect?.target?.tagName}`));
      record(`reduced motion @${w}: no running animations/transitions`, a.length === 0, a.join(', '));
    } catch (e) {
      record(`reduced motion @${w}`, false, e.message);
    } finally {
      await ctx.close();
    }
  }
}

async function lighthouse() {
  const chromePath = chromium.executablePath();
  const profile = mkdtempSync(join(tmpdir(), 'aa-lh-'));
  const port = 9300 + Math.floor(Math.random() * 500);
  const proc = spawn(chromePath, [
    `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--headless=new', '--no-first-run',
    '--no-default-browser-check', '--disable-gpu', 'about:blank',
  ], { stdio: 'ignore' });
  try {
    for (let i = 0; i < 50; i++) {
      try { const r = await fetch(`http://127.0.0.1:${port}/json/version`); if (r.ok) break; } catch {}
      await new Promise((r) => setTimeout(r, 200));
    }
    const mod = await import(pathToFileURL(join(NM, 'lighthouse/core/index.js')).href);
    const run = mod.default;
    const res = await run(BASE.href, {
      port, output: 'json', logLevel: 'error',
      onlyCategories: ['accessibility', 'performance', 'best-practices', 'seo'],
    });
    writeFileSync(join(OUT, 'lighthouse.json'), res.report);
    const cats = res.lhr.categories;
    const sc = Object.fromEntries(Object.entries(cats).map(([k, v]) => [k, Math.round((v.score ?? 0) * 100)]));
    extra.lighthouse = sc;
    const failing = Object.values(res.lhr.audits).filter((a) => a.score !== null && a.score < 1 && a.scoreDisplayMode !== 'informative' && a.scoreDisplayMode !== 'notApplicable' && a.scoreDisplayMode !== 'manual')
      .map((a) => `${a.id}=${a.score}`);
    extra.lighthouseFailingAudits = failing;
    record('lighthouse accessibility = 100', sc.accessibility === 100, `${sc.accessibility}`);
    record('lighthouse performance >= 90', sc.performance >= 90, `${sc.performance}`);
  } catch (e) {
    record('lighthouse', false, e.stack || e.message);
  } finally {
    proc.kill('SIGKILL');
    await new Promise((r) => setTimeout(r, 300));
    rmSync(profile, { recursive: true, force: true });
  }
}

function writeReports() {
  const allPass = results.every((r) => r.pass);
  writeFileSync(join(OUT, 'report.json'), JSON.stringify({ base: BASE.href, generated: new Date().toISOString(), pass: allPass, results, extra }, null, 2));
  const L = [`# Verify report`, '', `Base: ${BASE.href}  `, `Overall: **${allPass ? 'PASS' : 'FAIL'}**`, '', '| Result | Check | Detail |', '|---|---|---|'];
  for (const r of results) L.push(`| ${r.pass ? 'PASS' : '**FAIL**'} | ${r.name} | ${String(r.detail).replace(/\|/g, '\\|').replace(/\n/g, ' ').slice(0, 400)} |`);
  if (extra.lighthouse) {
    L.push('', '## Lighthouse (mobile)', '', Object.entries(extra.lighthouse).map(([k, v]) => `- ${k}: ${v}`).join('\n'));
    if (extra.lighthouseFailingAudits?.length) L.push('', 'Audits below 1: ' + extra.lighthouseFailingAudits.join(', '));
  }
  for (const [k, v] of Object.entries(extra)) {
    if (k.startsWith('axe-') && v.length) {
      L.push('', `## ${k} violations`);
      for (const x of v) {
        L.push(`- **${x.id}** (${x.impact}): ${x.help}`);
        for (const n of x.nodes.slice(0, 8)) L.push(`  - \`${n.target}\` ${n.summary || ''}`);
      }
    }
  }
  if (extra.transfer) L.push('', '## Transfer @375', '', `Total ${extra.transfer.kb} KB`, ...extra.transfer.files.map((f) => `- ${f[0]} ${(f[1] / 1024).toFixed(1)} KB`));
  if (extra.keyboard) {
    L.push('', '## Keyboard pass', '', '| # | element | name | box | indicator |', '|---|---|---|---|---|');
    for (const k of extra.keyboard) L.push(`| ${k.step} | <${k.tag}> ${String(k.text || '').replace(/\|/g, '/')} | ${String(k.name || '').replace(/\|/g, '/')} | ${k.box ? `${k.box.x},${k.box.y} ${k.box.w}x${k.box.h}` : ''} | ${k.visibleIndicator ? (k.outline || k.boxShadow) : 'NONE'} |`);
  }
  L.push('', `Demo focused strip stops: ${extra.demoFocusedStrip ?? 'n/a'}`);
  writeFileSync(join(OUT, 'report.md'), L.join('\n') + '\n');
  return allPass;
}

let exit = 1;
try {
  const browser = await chromium.launch();
  try {
    await shots(browser);
    await demo(browser);
    await keyboard(browser);
    await axeAndChecks(browser);
  } finally {
    await browser.close();
  }
  await lighthouse();
  exit = writeReports() ? 0 : 1;
} catch (e) {
  record('harness crashed', false, e.stack || e.message);
  writeReports();
}
process.exit(exit);
