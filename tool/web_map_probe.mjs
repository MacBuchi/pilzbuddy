// Hauptthread-Messung der Web-Karte im Headless-Chromium (#689).
//
// Dieselbe Probe wie in docs/map-performance.md („Karte hinter der
// Anmeldung", Hebel A/B1/C): Telefon-Ansicht 412 × 860 bei DPR 2 mit
// Touch, Laden bis zur Ruhe, dann fünf Touch-Wischer im Abstand von
// 2,5 s (× Drosselung). Gezählt werden Long Tasks
// (PerformanceObserver 'longtask') und Bildlücken über 50 ms
// (requestAnimationFrame), getrennt nach Phase.
//
//   PB_EMAIL=… PB_PASSWORD=… \
//   NODE_EXTRA_CA_CERTS=/pfad/zum/ca-bundle.crt \
//   node tool/web_map_probe.mjs [--engine flutter|maplibre] [--throttle 1|4]
//                               [--layers] [--runs N] [--url URL]
//                               [--screenshot datei.png]
//
// Die Zugangsdaten kommen NUR aus der Umgebung (dieselben Namen wie in
// seed_screenshot_data.py; das Testkonto steht im Austauschordner des
// Betreibers, in der Cloud als Umgebungsvariable) — ein Testkonto, nie das
// eigene. Angemeldet wird über GoTrue (Passwort-Grant) aus der Seite
// heraus; die Sitzung landet unter dem Schlüssel, den supabase_flutter
// im Web liest (`sb-<projekt>-auth-token`), danach lädt die App neu.
// So misst der Lauf die Karte und nicht das Anmeldeformular.
//
// Netz: Hinter einem TLS-prüfenden Proxy kennt Chromium dessen CA nicht.
// Jede Anfrage geht deshalb über `route.fetch()` (Node-Seite, liest
// HTTPS_PROXY und NODE_EXTRA_CA_CERTS); ohne Proxy ist das ein Umweg
// ohne Wirkung. Playwright kommt aus der globalen Installation
// (`npm root -g`) oder aus PLAYWRIGHT_MODULE.

import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import path from 'node:path';

const require = createRequire(import.meta.url);
const playwrightPath = process.env.PLAYWRIGHT_MODULE ??
  path.join(execSync('npm root -g').toString().trim(), 'playwright');
const { chromium } = require(playwrightPath);

const SUPABASE_URL = 'https://tntlujexvdtkynxbrdsn.supabase.co';
const SUPABASE_KEY = 'sb_publishable_uJvwpsHNh3lkD7gd-8Ym2Q_t7TBnqpO';
const SESSION_KEY = 'sb-tntlujexvdtkynxbrdsn-auth-token';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return fallback;
  const next = process.argv[i + 1];
  return next === undefined || next.startsWith('--') ? true : next;
}

const engine = arg('engine', 'flutter');
const throttle = Number(arg('throttle', '1'));
const layers = arg('layers', false) === true;
const runs = Number(arg('runs', '2'));
const baseUrl = arg('url', 'https://macbuchi.github.io/pilzbuddy-preview/');
const screenshot = arg('screenshot', null);
const loadSeconds = 55 * throttle;
const panGapMs = 2500 * throttle;
const settleMs = 5000 * throttle;

const email = process.env.PB_EMAIL;
const password = process.env.PB_PASSWORD;
if (!email || !password) {
  console.error('PB_EMAIL und PB_PASSWORD fehlen in der Umgebung.');
  process.exit(2);
}
if (!['flutter', 'maplibre'].includes(engine)) {
  console.error('--engine ist flutter oder maplibre');
  process.exit(2);
}

// Vor dem ersten Skript der App: Messfühler und Einstellungen. Die
// SharedPreferences liegen im Web als `flutter.<schlüssel>` mit
// JSON-Wert. Touren, Sicherheitshinweis und Neuheiten-Blatt sind als
// gesehen markiert, damit kein Overlay die Wischer schluckt.
const initScript = ({ layers }) => {
  const set = (k, v) => localStorage.setItem(`flutter.${k}`, JSON.stringify(v));
  set('forest_layer_enabled', layers);
  set('contour_layer_enabled', layers);
  set('map_tour_seen_3', true);
  set('safety_note_seen', true);
  set('highlights_seen_version_3', '999.0.0');
  window.__probe = { phase: 'load', tasks: [], gaps: [] };
  new PerformanceObserver((list) => {
    for (const e of list.getEntries()) {
      window.__probe.tasks.push({ phase: window.__probe.phase, d: e.duration });
    }
  }).observe({ type: 'longtask', buffered: true });
  let last = performance.now();
  const tick = (t) => {
    const gap = t - last;
    if (gap > 50) window.__probe.gaps.push({ phase: window.__probe.phase, d: gap });
    last = t;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
};

async function touchPan(cdp, x, y, dx, dy, steps = 12) {
  const point = (px, py) => [{ x: px, y: py, id: 1 }];
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: point(x, y) });
  for (let i = 1; i <= steps; i++) {
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: point(x + (dx * i) / steps, y + (dy * i) / steps),
    });
    await new Promise((r) => setTimeout(r, 16));
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

function summarize(probe, phase) {
  const tasks = probe.tasks.filter((t) => t.phase === phase);
  const gaps = probe.gaps.filter((g) => g.phase === phase);
  const sum = tasks.reduce((a, t) => a + t.d, 0);
  const max = tasks.reduce((a, t) => Math.max(a, t.d), 0);
  return {
    phase,
    longTasks: tasks.length,
    blockedS: +(sum / 1000).toFixed(2),
    longestS: +(max / 1000).toFixed(2),
    gapsOver50ms: gaps.length,
  };
}

async function oneRun(browser, n) {
  const ctx = await browser.newContext({
    viewport: { width: 412, height: 860 },
    deviceScaleFactor: 2,
    hasTouch: true,
    isMobile: true,
    serviceWorkers: 'block',
  });
  let external = 0;
  const origin = new URL(baseUrl).origin;
  await ctx.route('**/*', async (route) => {
    if (!route.request().url().startsWith(origin)) external++;
    try {
      await route.fulfill({ response: await route.fetch() });
    } catch {
      // Abgebrochene Kachel-Aufträge (die Karte ist weitergewandert)
      // landen hier; für die Messung zählt nur der Hauptthread.
      await route.abort().catch(() => {});
    }
  });
  const page = await ctx.newPage();

  // Anmelden auf dem Origin der App, dann Sitzung ablegen.
  await page.goto(new URL('404-probe', baseUrl).href).catch(() => {});
  const login = await page.evaluate(async ({ url, key, sessionKey, email, password }) => {
    const r = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    const body = await r.json();
    if (!r.ok) return { ok: false, status: r.status, msg: body.msg ?? body.error_description };
    localStorage.setItem(sessionKey, JSON.stringify(body));
    return { ok: true };
  }, { url: SUPABASE_URL, key: SUPABASE_KEY, sessionKey: SESSION_KEY, email, password });
  if (!login.ok) throw new Error(`Anmeldung gescheitert: ${login.status} ${login.msg}`);

  await page.addInitScript(initScript, { layers });
  const cdp = await ctx.newCDPSession(page);
  if (throttle > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });

  const target = new URL(baseUrl);
  target.searchParams.set('maplibre', engine === 'maplibre' ? '1' : '0');
  await page.goto(target.href, { waitUntil: 'load' });
  await page.waitForTimeout(loadSeconds * 1000);

  const engineSeen = await page.evaluate(() => ({
    maplibre: !!document.querySelector('.maplibregl-map'),
    wasm: performance.getEntriesByType('resource').some((e) => e.name.endsWith('main.dart.wasm')),
  }));

  await page.evaluate(() => { window.__probe.phase = 'pans'; });
  for (let i = 0; i < 5; i++) {
    await touchPan(cdp, 206, 520, i % 2 ? 120 : -120, i % 2 ? -120 : 120);
    await page.waitForTimeout(panGapMs);
  }
  await page.waitForTimeout(settleMs);

  const probe = await page.evaluate(() => window.__probe);
  if (screenshot) {
    const file = runs > 1 ? screenshot.replace(/(\.png)?$/, `-${n}.png`) : screenshot;
    await page.screenshot({ path: file });
  }
  await ctx.close();
  return { run: n, engineSeen, external, load: summarize(probe, 'load'), pans: summarize(probe, 'pans') };
}

const browser = await chromium.launch({
  proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined,
});
try {
  console.log(JSON.stringify({ engine, throttle, layers, url: baseUrl }));
  for (let n = 1; n <= runs; n++) {
    console.log(JSON.stringify(await oneRun(browser, n)));
  }
} finally {
  await browser.close();
}
