#!/usr/bin/env node
// v2 audit and screenshot harness for the Agent Awake landing page.
// Usage: NODE_PATH=~/.cache/agent-awake-pw/node_modules node site/scripts/verify.mjs <dist-dir | base-url> <out-dir>
// A directory is served on a free port bound to 127.0.0.1. Either way the page must contain "Agent Awake" before any check runs.
// Spec: v2/STANDARD.md (Loop steps 3 and 4) and the design skill's section 5 checklist.
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, mkdtempSync, rmSync, statSync, existsSync } from 'node:fs';
import { createServer } from 'node:net';
import { join, resolve } from 'node:path';
import { homedir, tmpdir } from 'node:os';

const [baseArg, outArg] = process.argv.slice(2);
if (!baseArg || !outArg) {
  console.error('usage: node verify.mjs <dist-dir | base-url> <out-dir>');
  process.exit(2);
}
const T0 = Date.now();
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
  m: { width: 390, height: 844 },
  s: { width: 320, height: 700 },
};

const newCtx = (browser, opts = {}) => {
  const { size = 'd', ...rest } = opts;
  return browser.newContext({ viewport: SIZES[size], deviceScaleFactor: 1, ...rest });
};
const loadPage = async (ctx) => {
  const page = await ctx.newPage();
  await page.goto(BASE.href, { waitUntil: 'load' });
  return page;
};

// Wait for images near the viewport (lazy ones included) to finish, then let reveal effects settle.
async function settle(page, ms = 500) {
  await page.evaluate(async () => {
    const near = [...document.images].filter((i) => {
      const r = i.getBoundingClientRect();
      return r.bottom > -200 && r.top < innerHeight + 200;
    });
    const done = Promise.all(near.map((i) => (i.complete ? 0 : new Promise((r) => {
      i.addEventListener('load', r, { once: true });
      i.addEventListener('error', r, { once: true });
    }))));
    await Promise.race([done, new Promise((r) => setTimeout(r, 4000))]);
  });
  await page.waitForTimeout(ms);
}

// Scroll to the footer in viewport-sized steps (loads lazy images, fires reveals), return to the top.
async function scrollThrough(page, step) {
  for (let y = 0; ; y += step) {
    const max = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
    await page.evaluate((v) => window.scrollTo(0, v), Math.min(y, max));
    await settle(page, 250);
    if (y >= max) break;
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(300);
}

// ---- in-page audit (runs at scroll 0, 1440 wide) ----
const audit = () => {
  const sel = (el) => {
    const parts = [];
    for (let e = el, depth = 0; e && e.nodeType === 1 && depth < 4; e = e.parentElement, depth++) {
      let p = e.tagName.toLowerCase();
      if (e.id) { parts.unshift(`${p}#${e.id}`); break; }
      const cls = [...e.classList].slice(0, 2).join('.');
      if (cls) p += '.' + cls;
      parts.unshift(p);
      if (e === document.body) break;
    }
    return parts.join(' > ');
  };
  const absTop = (r) => r.top + scrollY;
  const quote = (s) => s.trim().replace(/^["']|["']$/g, '');
  const firstFamily = (ff) => quote(ff.split(',')[0]);
  const BAD = ['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE'];

  // text-bearing visible elements
  const texts = new Map();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; (n = walker.nextNode());) {
    if (!n.nodeValue.trim()) continue;
    const el = n.parentElement;
    if (!el || texts.has(el) || BAD.includes(el.tagName)) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 1 || r.height <= 1) continue; // display:none, sr-only
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || +cs.opacity === 0) continue;
    let px = parseFloat(cs.fontSize);
    if (el instanceof SVGElement && el.ownerSVGElement) {
      const svg = el.ownerSVGElement;
      const vb = svg.viewBox.baseVal;
      if (vb && vb.width) px *= svg.getBoundingClientRect().width / vb.width;
    }
    texts.set(el, { el, px: +px.toFixed(2), family: firstFamily(cs.fontFamily), top: absTop(r), text: n.nodeValue.trim().replace(/\s+/g, ' ').slice(0, 40), cs });
  }
  const items = [...texts.values()];

  // 1 families
  const fam = {};
  for (const t of items) {
    const k = t.family.toLowerCase();
    (fam[k] ||= { name: t.family, count: 0, sample: sel(t.el) }).count++;
  }
  const faces = [...new Set([...document.fonts].filter((f) => f.status === 'loaded').map((f) => quote(f.family).toLowerCase()))];

  // hero and below-hero sizes
  const h1 = document.querySelector('h1');
  const main = document.querySelector('main');
  const hero = document.querySelector('[data-hero], .hero') || (h1 && h1.closest('section')) ||
    main?.querySelector('section') || (h1 && h1.parentElement);
  const heroBottom = hero ? absTop(hero.getBoundingClientRect()) + hero.getBoundingClientRect().height : 0;
  const sizes = {};
  for (const t of items) {
    if (t.top < heroBottom - 1) continue;
    if (t.el.closest('h1') || t.el.closest('body > header, [role=banner]')) continue;
    (sizes[t.px] ||= { px: t.px, count: 0, sample: sel(t.el), text: t.text }).count++;
  }

  // 3 min size
  const smallest = [...items].sort((a, b) => a.px - b.px).slice(0, 5).map((t) => ({ px: t.px, sel: sel(t.el), text: t.text }));

  // 4 uppercase + letter-spacing, 5 transition all
  const upper = [];
  const transAll = [];
  const nonzero = (ls) => ls !== 'normal' && parseFloat(ls) !== 0;
  const durPositive = (d) => d.split(',').some((x) => parseFloat(x) > 0);
  const check = (el, pseudo) => {
    const cs = getComputedStyle(el, pseudo);
    if (pseudo && (cs.content === 'none' || cs.content === 'normal')) return;
    if (cs.textTransform === 'uppercase' && nonzero(cs.letterSpacing)) {
      upper.push({ sel: sel(el) + (pseudo || ''), letterSpacing: cs.letterSpacing });
    }
    if (cs.transitionProperty.split(',').map((s) => s.trim()).includes('all') && durPositive(cs.transitionDuration)) {
      transAll.push({ sel: sel(el) + (pseudo || ''), duration: cs.transitionDuration });
    }
  };
  for (const el of document.body.querySelectorAll('*')) {
    if (BAD.includes(el.tagName)) continue;
    check(el);
    check(el, '::before');
    check(el, '::after');
  }
  // stylesheet source: catches :hover/:focus rules the computed pass cannot see
  const cssAll = [];
  const walkRules = (rules, ctx) => {
    for (const r of rules) {
      if (r.cssRules && !r.style) walkRules(r.cssRules, ctx);
      if (r.style) {
        const tp = r.style.getPropertyValue('transition-property');
        const tr = r.style.getPropertyValue('transition');
        const hit = (/(^|[\s,])all([\s,]|$)/.test(tp) && tp) || (/(^|[\s,])all([\s,]|$)/.test(tr) && tr);
        if (hit) cssAll.push(`${r.selectorText}: ${hit}`);
      }
    }
  };
  for (const ss of document.styleSheets) { try { walkRules(ss.cssRules); } catch {} }

  // 6 dashes
  const DASH = /\u2014|[\s\u00a0]\u2013[\s\u00a0]/;
  const dashes = [];
  const ctxOf = (s, i) => s.slice(Math.max(0, i - 25), i + 25).replace(/\s+/g, ' ');
  const body = document.body.innerText;
  for (const line of body.split('\n')) { const m = DASH.exec(line); if (m) dashes.push({ where: 'text', ctx: ctxOf(line, m.index) }); }
  for (const el of document.querySelectorAll('[alt],[aria-label]')) {
    for (const a of ['alt', 'aria-label']) {
      const v = el.getAttribute(a);
      const m = v && DASH.exec(v);
      if (m) dashes.push({ where: `${a} on ${sel(el)}`, ctx: ctxOf(v, m.index) });
    }
  }

  // 7 h1
  const h1r = h1?.getBoundingClientRect();
  let h1Text = null;
  if (h1) { const rg = document.createRange(); rg.selectNodeContents(h1); h1Text = rg.getBoundingClientRect().width; }

  // 10 bleed
  const hdr = document.querySelector('body > header, header, [role=banner]');
  const cands = [];
  const firstMain = main?.firstElementChild;
  for (const [label, el] of [['hero', hero], ['main first child', firstMain], ['first section', document.querySelector('section')]]) {
    if (!el) continue;
    const r = el.getBoundingClientRect();
    const media = el.matches('img, picture, video, svg') ? el : el.querySelector('img, picture, video, svg');
    cands.push({ label, sel: sel(el), top: +absTop(r).toFixed(1), mediaTop: media ? +absTop(media.getBoundingClientRect()).toFixed(1) : null });
  }
  let header = null;
  if (hdr) {
    const cs = getComputedStyle(hdr);
    const sides = ['Top', 'Right', 'Bottom', 'Left'].filter((s) => cs[`border${s}Style`] !== 'none' && parseFloat(cs[`border${s}Width`]) > 0 && !/rgba\([^)]*,\s*0\)|transparent/.test(cs[`border${s}Color`]));
    header = { sel: sel(hdr), borders: sides.map((s) => `${s} ${cs[`border${s}Width`]} ${cs[`border${s}Style`]} ${cs[`border${s}Color`]}`), position: cs.position };
  }

  // 11 pills
  const pills = [];
  for (const el of document.body.querySelectorAll('*')) {
    if (['A', 'BUTTON', 'INPUT', 'SELECT', 'TEXTAREA'].includes(el.tagName) || el.getAttribute('role') === 'button' || el.getAttribute('role') === 'link') continue;
    if (BAD.includes(el.tagName)) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 1 || r.height <= 1) continue;
    const cs = getComputedStyle(el);
    const rad = cs.borderTopLeftRadius;
    let pill = false;
    if (rad.endsWith('%')) pill = parseFloat(rad) >= 50;
    else { const v = parseFloat(rad); pill = v > 0 && (v >= 999 || v >= r.height / 2); }
    if (pill) pills.push({ sel: sel(el), radius: rad, size: `${Math.round(r.width)}x${Math.round(r.height)}`, text: (el.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 30) });
  }

  return {
    families: Object.values(fam).sort((a, b) => b.count - a.count),
    faces,
    hero: hero ? sel(hero) : null,
    heroBottom: Math.round(heroBottom),
    sizes: Object.values(sizes).sort((a, b) => b.count - a.count),
    smallest,
    textElements: items.length,
    upper,
    transAll,
    cssAll,
    dashes,
    h1: h1r ? { width: +h1r.width.toFixed(1), textWidth: +h1Text.toFixed(1), sel: sel(h1), top: +absTop(h1r).toFixed(1) } : null,
    cands,
    header,
    pills,
  };
};

const focusInfo = () => {
  const ids = (window.__kbIds ||= new WeakMap());
  const kbKey = (el) => { if (!ids.has(el)) ids.set(el, (window.__kbN = (window.__kbN || 0) + 1)); return 'el' + ids.get(el); };
  const el = document.activeElement;
  if (!el || el === document.body || el === document.documentElement) return null;
  const cs = getComputedStyle(el);
  const r = el.getBoundingClientRect();
  const outline = cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0 && !/rgba\(\d+,\s*\d+,\s*\d+,\s*0\)|transparent/.test(cs.outlineColor);
  const shadow = cs.boxShadow && cs.boxShadow !== 'none';
  const labelled = el.getAttribute('aria-labelledby');
  const name = el.getAttribute('aria-label') ||
    (labelled && labelled.split(/\s+/).map((i) => document.getElementById(i)?.textContent.trim()).filter(Boolean).join(' ')) ||
    el.getAttribute('alt') ||
    (el.labels && el.labels.length && [...el.labels].map((l) => l.textContent.trim()).join(' ')) ||
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
    key: kbKey(el),
  };
};

// ---- screenshots ----
async function shots(browser) {
  // desktop: opening viewport, then every 900 px step to the footer
  {
    const ctx = await newCtx(browser, { size: 'd' });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(1200);
      const files = [];
      for (let i = 0, y = 0; ; i++, y += 900) {
        const max = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
        const at = Math.min(y, max);
        if (i > 0) {
          await page.evaluate((v) => window.scrollTo(0, v), at);
          await settle(page, 600);
          // the bag-trip chart draws once (about 2.5 s) when it is half in view: let it finish before the shot
          const inView = await page.evaluate(() => {
            const el = document.querySelector('#strip .strip-fig');
            if (!el) return false;
            const r = el.getBoundingClientRect();
            return r.top < innerHeight * 0.5 && r.bottom > innerHeight * 0.5 || (r.top >= 0 && r.bottom <= innerHeight);
          });
          if (inView) await page.waitForTimeout(2800);
        }
        else await settle(page, 0);
        const f = `desktop-${String(i).padStart(2, '0')}.png`;
        await page.screenshot({ path: join(OUT, f) });
        files.push(f);
        if (y >= max) break;
      }
      extra.desktopShots = files;
    } catch (e) { record('screenshots desktop', false, e.message); } finally { await ctx.close(); }
  }
  // mobile: opening viewport and full page
  {
    const ctx = await newCtx(browser, { size: 'm' });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(1200);
      await settle(page, 0);
      await page.screenshot({ path: join(OUT, 'mobile-00.png') });
      await scrollThrough(page, 844);
      await page.screenshot({ path: join(OUT, 'mobile-full.png'), fullPage: true });
    } catch (e) { record('screenshots mobile', false, e.message); } finally { await ctx.close(); }
  }
  // the chart element on its own, settled (reduced motion: no animation), desktop and phone
  for (const [file, size] of [['strip-desktop.png', 'd'], ['strip-mobile.png', 'm']]) {
    const ctx = await newCtx(browser, { size, reducedMotion: 'reduce' });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      await page.evaluate(() => { document.getElementById('top').style.visibility = 'hidden'; }); // the fixed header would sit over an element shot
      await page.locator('#strip').scrollIntoViewIfNeeded();
      await page.waitForTimeout(600);
      await page.locator('#strip').screenshot({ path: join(OUT, file) });
    } catch (e) { record(`screenshot ${file}`, false, e.message); } finally { await ctx.close(); }
  }
  // 1440 opening with reduced motion and with JS off
  for (const [file, opts] of [['desktop-reduced.png', { reducedMotion: 'reduce' }], ['desktop-nojs.png', { javaScriptEnabled: false }]]) {
    const ctx = await newCtx(browser, { size: 'd', ...opts });
    try {
      const page = await loadPage(ctx);
      if (opts.javaScriptEnabled !== false) await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(1000);
      await page.screenshot({ path: join(OUT, file) });
    } catch (e) { record(`screenshot ${file}`, false, e.message); } finally { await ctx.close(); }
  }
}

// ---- keyboard ----
async function keyboard(browser) {
  const ctx = await newCtx(browser, { size: 'd' });
  try {
    const page = await loadPage(ctx);
    await page.evaluate(() => document.fonts.ready);
    const log = [];
    let firstKey = null;
    let wrapped = false;
    for (let i = 0; i < 60; i++) {
      await page.keyboard.press('Tab');
      const info = await page.evaluate(focusInfo);
      if (!info) { log.push({ step: i + 1, tag: 'body', note: 'focus left the document' }); continue; }
      if (firstKey === null) firstKey = info.key;
      else if (info.key === firstKey) { wrapped = true; break; }
      log.push({ step: i + 1, ...info });
      if (i < 3) await page.screenshot({ path: join(OUT, `focus-${i + 1}.png`) });
    }
    extra.keyboardWrapped = wrapped;
    extra.keyboard = log;
    const first = log[0];
    let skipOk = false;
    let skipDetail = 'no focus after first Tab';
    if (first && first.tag === 'a' && first.href && first.href.startsWith('#') && first.href.length > 1) {
      const exists = await page.evaluate((h) => !!document.getElementById(decodeURIComponent(h.slice(1))), first.href);
      skipOk = exists;
      skipDetail = `${first.href} -> ${exists ? 'target exists' : 'MISSING target'} (text "${first.text}")`;
    } else if (first) skipDetail = `first focus is <${first.tag}> "${first.text}" href=${first.href}`;
    record('keyboard pass returned to the first element within 60 Tabs', wrapped, `${log.filter((l) => l.tag !== 'body').length} stops`);
    record('first Tab lands on skip link with existing target', skipOk, skipDetail);
    const bad = log.filter((l) => l.tag !== 'body' && !l.visibleIndicator);
    record('every focused element has a visible focus indicator (outline/box-shadow)', bad.length === 0 && log.length > 0,
      bad.length ? bad.map((b) => `step ${b.step} <${b.tag}> "${b.text}"`).join('; ') : `${log.length} stops checked`);
    const unnamed = log.filter((l) => l.tag !== 'body' && !l.name);
    record('every focused element has an accessible name', unnamed.length === 0, unnamed.map((b) => `step ${b.step} <${b.tag}>`).join('; '));
  } finally { await ctx.close(); }
}

// ---- the eleven v2 checks ----
async function v2Checks(browser) {
  // 1-7, 10, 11 on one 1440 load
  {
    const ctx = await newCtx(browser, { size: 'd' });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(800);
      await scrollThrough(page, 900);
      const a = await page.evaluate(audit);
      extra.audit = a;
      const fams = a.families.map((f) => `${f.name} x${f.count}`).join(', ');
      record('1 font families <=2 (rendered text first family; loaded faces)', a.families.length <= 2 && a.faces.length <= 2,
        `rendered ${a.families.length}: ${fams}; loaded faces ${a.faces.length}: ${a.faces.join(', ') || 'none'}`);
      record('2 distinct font sizes below the hero <=3 (excl. h1, header)', a.sizes.length <= 3,
        `hero "${a.hero}" ends y=${a.heroBottom}; ${a.sizes.length} sizes: ` + a.sizes.map((s) => `${s.px}px x${s.count} (${s.sample})`).join('; '));
      const s0 = a.smallest[0];
      record('3 min font size >=13px', !!s0 && s0.px >= 13, s0 ? `smallest ${s0.px}px ${s0.sel} "${s0.text}"; ${a.smallest.filter((s) => s.px < 13).length} of 5 smallest below 13` : 'no text found');
      record('4 no uppercase text with letter-spacing', a.upper.length === 0, a.upper.slice(0, 8).map((u) => `${u.sel} ${u.letterSpacing}`).join('; ') + (a.upper.length > 8 ? ` (+${a.upper.length - 8})` : ''));
      const t = [...a.transAll.map((x) => `computed ${x.sel} ${x.duration}`), ...a.cssAll.map((x) => `css ${x}`)];
      record('5 no transition-property all', t.length === 0, t.slice(0, 8).join('; ') + (t.length > 8 ? ` (+${t.length - 8})` : ''));
      record('6 no em-dash or spaced en-dash in visible text, alt, aria-label', a.dashes.length === 0,
        a.dashes.slice(0, 6).map((d) => `${d.where}: "${d.ctx}"`).join('; ') + (a.dashes.length > 6 ? ` (+${a.dashes.length - 6})` : ''));
      record('7 h1 width >=70% of 1440 (1008px)', !!a.h1 && a.h1.width >= 1008,
        a.h1 ? `${a.h1.width}px box (${(a.h1.width / 14.4).toFixed(0)}%), text lines ${a.h1.textWidth}px, ${a.h1.sel}` : 'no h1');
      const bleed = a.cands.some((c) => c.top <= 0.5 || (c.mediaTop !== null && c.mediaTop <= 0.5));
      const hb = a.header ? a.header.borders : [];
      record('10 hero bleeds to y=0 and header has no border', bleed && hb.length === 0,
        `${a.cands.map((c) => `${c.label} top=${c.top}${c.mediaTop !== null ? ` media=${c.mediaTop}` : ''}`).join(', ') || 'no hero candidate'}; header ${a.header ? `${a.header.sel} (${a.header.position}) borders: ${hb.join(', ') || 'none'}` : 'none'}`);
      console.log(`INFO 11 pill-like non-interactive elements: ${a.pills.length}`);
      extra.pillsInfo = a.pills;
    } catch (e) {
      record('v2 computed-style checks', false, e.stack || e.message);
    } finally { await ctx.close(); }
  }

  // 8 overflow
  for (const size of ['s', 'm', 'd']) {
    const w = SIZES[size].width;
    const ctx = await newCtx(browser, { size });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      await scrollThrough(page, SIZES[size].height);
      const o = await page.evaluate(() => {
        const iw = window.innerWidth;
        const wide = [];
        for (const el of document.body.querySelectorAll('*')) {
          const r = el.getBoundingClientRect();
          if (r.width > 0 && r.right > iw + 1 && getComputedStyle(el).position !== 'fixed') {
            wide.push(`${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''}${el.classList[0] ? '.' + el.classList[0] : ''} right=${Math.round(r.right)}`);
            if (wide.length >= 4) break;
          }
        }
        return { sw: document.documentElement.scrollWidth, bw: document.body.scrollWidth, iw, wide };
      });
      record(`8 no horizontal overflow @${w}`, Math.max(o.sw, o.bw) <= o.iw,
        `scrollWidth ${o.sw}/${o.bw} vs innerWidth ${o.iw}${o.wide.length ? '; wide: ' + o.wide.join(', ') : ''}`);
    } catch (e) { record(`8 overflow @${w}`, false, e.message); } finally { await ctx.close(); }
  }

  // 9 axe at 1440 and 390
  for (const size of ['d', 'm']) {
    const w = SIZES[size].width;
    const ctx = await newCtx(browser, { size });
    try {
      const page = await loadPage(ctx);
      await page.evaluate(() => document.fonts.ready);
      await scrollThrough(page, SIZES[size].height);
      const r = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa', 'best-practice']).analyze();
      const v = r.violations.map((x) => ({
        id: x.id, impact: x.impact, help: x.help,
        nodes: x.nodes.map((n) => ({ target: n.target.join(' '), summary: n.failureSummary?.split('\n').slice(0, 3).join(' | ') })),
      }));
      extra[`axe-${w}`] = v;
      record(`9 axe zero violations @${w}`, v.length === 0, v.map((x) => `${x.id}(${x.nodes.length})`).join(', ') || `${r.passes.length} rules passed`);
    } catch (e) { record(`9 axe @${w}`, false, e.message); } finally { await ctx.close(); }
  }
}

// ---- structure, network, JS off, reduced motion ----
async function pageChecks(browser) {
  {
    const ctx = await newCtx(browser, { size: 'm' });
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
      const top = detail.sort((a, b) => b[1] - a[1]);
      extra.transfer = { kb: +kb.toFixed(1), files: top.slice(0, 12) };
      record('first-load transfer @390 < 300 KB (excl. video)', kb < 300, `${kb.toFixed(1)} KB; largest: ${top.slice(0, 3).map((d) => `${d[0]} ${(d[1] / 1024).toFixed(1)}KB`).join(', ')}`);
      const bannedRes = [['{{', /\{\{/], ['TODO', /\bTODO\b/], ['TBD', /\bTBD\b/], ['XX', /\bXX+\b/], ['IPv4-shaped string', /\b\d{1,3}(?:\.\d{1,3}){3}\b/]];
      const hits = bannedRes.filter(([, re]) => re.test(s.text)).map(([n, re]) => `${n}: "${(s.text.match(re) || [''])[0]}"`);
      record('page text has no {{, TODO, TBD, XX, IPv4', hits.length === 0, hits.join('; '));
    } catch (e) { record('first-load checks @390', false, e.message); } finally { await ctx.close(); }
  }

  // JS off: h1 and body copy visible, nothing hidden by a reveal class waiting for JS
  for (const size of ['d', 'm']) {
    const w = SIZES[size].width;
    const ctx = await newCtx(browser, { size, javaScriptEnabled: false });
    try {
      const page = await loadPage(ctx);
      await page.waitForTimeout(800);
      const r = await page.evaluate(() => {
        const h1 = document.querySelector('h1');
        const h1r = h1?.getBoundingClientRect();
        const eff = (el) => { let o = 1; for (let e = el; e; e = e.parentElement) o *= +getComputedStyle(e).opacity; return o; };
        const hidden = [];
        let n = 0;
        for (const el of document.querySelectorAll('main p, main h2, main h3, main li, main a, main button')) {
          const rr = el.getBoundingClientRect();
          if (rr.width <= 1 || rr.height <= 1 || !el.textContent.trim()) continue;
          n++;
          if (eff(el) < 0.1) hidden.push(`${el.tagName.toLowerCase()} "${el.textContent.trim().slice(0, 30)}"`);
        }
        return { h1: !!h1r && h1r.width > 0 && h1r.height > 0 && getComputedStyle(h1).visibility !== 'hidden', n, hidden: hidden.slice(0, 6), nh: hidden.length };
      });
      record(`JS off @${w}: h1 and content visible`, r.h1 && r.n > 0 && r.nh === 0, `h1 ${r.h1}, ${r.n} content nodes, ${r.nh} at opacity<0.1${r.hidden.length ? ': ' + r.hidden.join('; ') : ''}`);
    } catch (e) { record(`JS off @${w}`, false, e.message); } finally { await ctx.close(); }
  }

  for (const size of ['d', 'm']) {
    const w = SIZES[size].width;
    const ctx = await newCtx(browser, { size, reducedMotion: 'reduce' });
    try {
      const page = await loadPage(ctx);
      await page.waitForTimeout(2000);
      const a = await page.evaluate(() => document.getAnimations().map((x) => `${x.constructor.name}:${x.animationName || x.transitionProperty || x.id}:${x.effect?.target?.tagName}`));
      record(`reduced motion @${w}: no running animations/transitions`, a.length === 0, a.join(', '));
    } catch (e) { record(`reduced motion @${w}`, false, e.message); } finally { await ctx.close(); }
  }
}

async function lighthouse() {
  const chromePath = chromium.executablePath();
  const profile = mkdtempSync(join(tmpdir(), 'aa-lh-'));
  const port = await freePort();
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
    const res = await mod.default(BASE.href, {
      port, output: 'json', logLevel: 'error',
      onlyCategories: ['accessibility', 'performance', 'best-practices', 'seo'],
    }); // default Lighthouse config emulates a mobile device
    writeFileSync(join(OUT, 'lighthouse.json'), res.report);
    const sc = Object.fromEntries(Object.entries(res.lhr.categories).map(([k, v]) => [k, Math.round((v.score ?? 0) * 100)]));
    extra.lighthouse = sc;
    extra.lighthouseFailingAudits = Object.values(res.lhr.audits)
      .filter((a) => a.score !== null && a.score < 1 && !['informative', 'notApplicable', 'manual'].includes(a.scoreDisplayMode))
      .map((a) => `${a.id}=${a.score}`);
    record('9 lighthouse mobile accessibility = 100', sc.accessibility === 100, `${sc.accessibility}`);
    record('9 lighthouse mobile performance >= 90', sc.performance >= 90, `${sc.performance}`);
  } catch (e) {
    record('9 lighthouse mobile', false, e.stack || e.message);
  } finally {
    proc.kill('SIGKILL');
    await new Promise((r) => setTimeout(r, 300));
    rmSync(profile, { recursive: true, force: true });
  }
}

function writeReports() {
  const secs = Math.round((Date.now() - T0) / 1000);
  const allPass = results.every((r) => r.pass);
  writeFileSync(join(OUT, 'report.json'), JSON.stringify({ base: BASE.href, generated: new Date().toISOString(), seconds: secs, pass: allPass, results, extra }, null, 2));
  const cell = (s, n = 500) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ').slice(0, n);
  const L = ['# Verify report', '', `Base: ${BASE.href}  `, `Overall: **${allPass ? 'PASS' : 'FAIL'}**  `, `Run time: ${secs}s`, '', '| Result | Check | Evidence |', '|---|---|---|'];
  for (const r of results) L.push(`| ${r.pass ? 'PASS' : '**FAIL**'} | ${cell(r.name)} | ${cell(r.detail)} |`);
  const a = extra.audit;
  if (a) {
    L.push('', '## Font families (rendered text, first family)', '', ...a.families.map((f) => `- ${f.name}: ${f.count} elements, e.g. \`${f.sample}\``), `- Loaded faces (document.fonts): ${a.faces.join(', ') || 'none'}`);
    L.push('', `## Font sizes below the hero (hero \`${a.hero}\` ends y=${a.heroBottom})`, '', ...a.sizes.map((s) => `- ${s.px}px: ${s.count} elements, e.g. \`${s.sample}\` "${s.text}"`));
    L.push('', '## Smallest text', '', ...a.smallest.map((s) => `- ${s.px}px \`${s.sel}\` "${s.text}"`));
    if (a.upper.length) L.push('', '## Uppercase with letter-spacing', '', ...a.upper.map((u) => `- \`${u.sel}\` ${u.letterSpacing}`));
    if (a.transAll.length || a.cssAll.length) L.push('', '## transition: all', '', ...a.transAll.map((x) => `- computed \`${x.sel}\` ${x.duration}`), ...a.cssAll.map((x) => `- css \`${x}\``));
    if (a.dashes.length) L.push('', '## Dashes', '', ...a.dashes.map((d) => `- ${d.where}: "${d.ctx}"`));
    L.push('', `## Pill-like elements, informational (${a.pills.length})`, '', ...a.pills.slice(0, 40).map((p) => `- \`${p.sel}\` radius ${p.radius}, ${p.size} "${p.text}"`));
    if (a.pills.length > 40) L.push(`- (+${a.pills.length - 40} more)`);
  }
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
  if (extra.transfer) L.push('', '## Transfer @390', '', `Total ${extra.transfer.kb} KB`, ...extra.transfer.files.map((f) => `- ${f[0]} ${(f[1] / 1024).toFixed(1)} KB`));
  if (extra.keyboard) {
    L.push('', `## Keyboard pass (${extra.keyboard.filter((k) => k.tag !== 'body').length} stops; returned to the first element: ${extra.keyboardWrapped})`, '', '| # | element | name | box | indicator |', '|---|---|---|---|---|');
    for (const k of extra.keyboard) L.push(`| ${k.step} | <${k.tag}> ${String(k.text || '').replace(/\|/g, '/')} | ${String(k.name || '').replace(/\|/g, '/')} | ${k.box ? `${k.box.x},${k.box.y} ${k.box.w}x${k.box.h}` : ''} | ${k.visibleIndicator ? (k.outline || k.boxShadow) : 'NONE'} |`);
  }
  if (extra.desktopShots) L.push('', `## Screenshots`, '', `desktop: ${extra.desktopShots.join(', ')}; mobile-00.png, mobile-full.png, strip-desktop.png, strip-mobile.png, desktop-reduced.png, desktop-nojs.png`);
  writeFileSync(join(OUT, 'report.md'), L.join('\n') + '\n');
  return allPass;
}

let exit = 1;
try {
  const browser = await chromium.launch();
  try {
    await shots(browser);
    await v2Checks(browser);
    await pageChecks(browser);
    await keyboard(browser);
  } finally {
    await browser.close();
  }
  await lighthouse();
  exit = writeReports() ? 0 : 1;
  console.log(`done in ${Math.round((Date.now() - T0) / 1000)}s, report: ${join(OUT, 'report.md')}`);
} catch (e) {
  record('harness crashed', false, e.stack || e.message);
  writeReports();
}
process.exit(exit);
