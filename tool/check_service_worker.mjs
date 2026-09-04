// Prüft den Service Worker der Web-App gegen einen echten Chrome (#387).
//
//     node tool/check_service_worker.mjs build/web
//
// **Warum als eigenes Werkzeug.** Der Worker ist die riskanteste Stelle
// der PWA: Er entscheidet, ob die App ohne Netz startet, und ein Fehler
// darin ist von außen unsichtbar — `flutter analyze` sieht die Datei
// nicht, `flutter test` startet keinen Browser, und ein kaputter Worker
// scheitert still. Textprüfungen auf `web/sw.js` fangen Tippfehler, aber
// keine falsche Entscheidung.
//
// **Der Offline-Fall wird NICHT emuliert.** Der Webserver wird wirklich
// abgeschaltet. Alles andere wäre eine Aussage über die Emulation.
//
// Ohne Abhängigkeiten: Node bringt seit 22 ein globales `WebSocket` mit,
// und damit lässt sich das DevTools-Protokoll direkt sprechen.
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {existsSync} from 'node:fs';
import {readFile, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, extname, normalize} from 'node:path';

const ROOT = process.argv[2] ?? 'build/web';
const PORT = 8796;
const CDP_PORT = 9333;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

// Der Build trägt seinen Pfad im `<base href>` — die Seite muss unter
// genau dem ausgeliefert werden, sonst zeigt jede relative Adresse ins
// Leere. So prüft dasselbe Werkzeug Freigabe (/pilzbuddy/) und Vorschau.
const index = await readFile(join(ROOT, 'index.html'), 'utf8');
const base = index.match(/<base href="([^"]*)"/)?.[1] || '/';

const handler = async (req, res) => {
  try {
    let path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (!path.startsWith(base)) throw new Error('außerhalb');
    path = '/' + path.slice(base.length);
    if (path.endsWith('/')) path += 'index.html';
    const file = join(ROOT, normalize(path));
    const body = await readFile(file);
    res.writeHead(200, {
      'content-type': TYPES[extname(file)] ?? 'application/octet-stream',
    });
    res.end(body);
  } catch (_) {
    res.writeHead(404).end('nicht da');
  }
};

let server;
const startServer = async () => {
  server = createServer(handler);
  await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
};
const stopServer = async () => {
  server.closeAllConnections();
  await new Promise((r) => server.close(r));
};

function chromeBinary() {
  if (process.env.CHROME_EXECUTABLE) return process.env.CHROME_EXECUTABLE;
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium-browser',
    '/usr/bin/chromium',
  ];
  return candidates.find(existsSync) ?? 'google-chrome';
}

function rpc(ws) {
  let id = 0;
  const pending = new Map();
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const {resolve, reject} = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(JSON.stringify(message.error)))
                    : resolve(message.result);
    }
  });
  return (method, params = {}) =>
      new Promise((resolve, reject) => {
        const mid = ++id;
        pending.set(mid, {resolve, reject});
        ws.send(JSON.stringify({id: mid, method, params}));
      });
}

async function evaluate(send, expression) {
  const result = await send(
      'Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
  return result.result.value;
}

async function waitFor(send, expression, what, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      if (await evaluate(send, expression)) return;
    } catch (_) {
      // Während einer Navigation antwortet die Seite kurz nicht.
    }
    await sleep(300);
  }
  throw new Error(`Zeitlimit: ${what}`);
}

const ok = [];
const fail = [];
const check = (condition, text) => (condition ? ok : fail).push(text);

const profile = await mkdtemp(join(tmpdir(), 'pilzbuddy-sw-'));
const chrome = spawn(chromeBinary(), [
  '--headless=new',
  '--no-first-run',
  '--no-default-browser-check',
  '--no-sandbox',
  '--enable-unsafe-swiftshader',
  `--remote-debugging-port=${CDP_PORT}`,
  `--user-data-dir=${profile}`,
  'about:blank',
], {stdio: 'ignore'});

const url = `http://127.0.0.1:${PORT}${base}`;
let ws;
try {
  await startServer();

  // Chrome braucht einen Moment, bis das Protokoll offen ist.
  let targets;
  for (let attempt = 0; attempt < 40 && !targets; attempt++) {
    try {
      targets = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/list`)).json();
    } catch (_) {
      await sleep(500);
    }
  }
  if (!targets) throw new Error('Chrome antwortet nicht auf dem Debug-Port');

  ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  const send = rpc(ws);
  await send('Page.enable');
  await send('Runtime.enable');

  const APP = "!!document.querySelector('flutter-view, flt-glass-pane')";

  // 1 — der ERSTE Besuch. Frisch, damit gemessen wird, was ein neuer
  // Nutzer bekommt: Beim ersten Laden kontrolliert der Worker die Seite
  // noch nicht, der Cache entsteht erst durch das Vorwärmen.
  await send('Page.navigate', {url});
  await sleep(2000);
  await evaluate(send, `(async () => {
    for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister();
    for (const k of await caches.keys()) await caches.delete(k);
  })()`);
  await send('Page.navigate', {url: `${url}?frisch=1`});
  await waitFor(send, APP, 'die App rendert online');
  await waitFor(send, 'navigator.serviceWorker.controller !== null',
      'der Worker kontrolliert die Seite');

  const script = await evaluate(send, 'navigator.serviceWorker.controller.scriptURL');
  check(/\/sw\.js\?v=\d+$/.test(script), `der Worker läuft (${script})`);

  // CanvasKit vom CDN wäre offline tot — und schickte die IP jedes
  // Besuchers an Google, bevor irgendetwas eingeschaltet wurde.
  const fromCdn = await evaluate(send,
      "performance.getEntriesByType('resource').some(e => e.name.includes('flutter-canvaskit'))");
  check(fromCdn === false, `CanvasKit kommt aus dem eigenen Build (CDN: ${fromCdn})`);

  await sleep(12000); // das Vorwärmen zu Ende laufen lassen
  const caches1 = JSON.parse(await evaluate(send, `(async () => {
    const out = {};
    for (const name of await caches.keys()) {
      out[name] = (await (await caches.open(name)).keys()).length;
    }
    return JSON.stringify(out);
  })()`));
  const names = Object.keys(caches1);
  check(names.length === 1 && names[0].startsWith('pilzbuddy-'),
      `genau ein Cache, benannt nach der Bauversion: ${JSON.stringify(caches1)}`);
  check((caches1[names[0]] ?? 0) >= 10,
      `schon der erste Besuch füllt ihn (${caches1[names[0]]} Einträge)`);

  // 2 — der eigentliche Beweis: Server wirklich aus, dann neu laden.
  await stopServer();
  let reallyDown = false;
  try {
    await fetch(url, {signal: AbortSignal.timeout(2000)});
  } catch (_) {
    reallyDown = true;
  }
  check(reallyDown, 'der Webserver ist wirklich aus');

  await send('Page.navigate', {url});
  await waitFor(send, APP, 'die App rendert OHNE Server');
  check(true, 'die App startet ohne Server');

  // 3 — die Notbremse. Eine, die man nie gezogen hat, zählt nicht.
  await startServer();
  await send('Page.navigate', {url});
  await waitFor(send, 'navigator.serviceWorker.controller !== null', 'wieder online');
  await sleep(12000);
  await evaluate(send,
      "navigator.serviceWorker.controller.postMessage({type: 'unregister'})");
  await sleep(3000);
  // Geprüft wird der CACHE. Die Registrierung bleibt laut Spezifikation
  // gelistet, solange diese Seite noch von ihr kontrolliert wird — sie
  // verschwindet beim Verlassen. Genau deshalb lädt die Notbremse nicht
  // selbst neu.
  const left = await evaluate(send, '(async () => (await caches.keys()).length)()');
  check(left === 0, `die Notbremse räumt den Cache (übrig: ${left})`);
} catch (error) {
  fail.push(`ABBRUCH: ${error.message}`);
} finally {
  try { ws?.close(); } catch (_) { /* egal */ }
  chrome.kill('SIGKILL');
  try { await stopServer(); } catch (_) { /* schon zu */ }
  await rm(profile, {recursive: true, force: true});
}

for (const line of ok) console.log('  OK   ' + line);
for (const line of fail) console.log('  FEHL ' + line);
console.log(fail.length ? '\nService Worker: FEHLGESCHLAGEN' : '\nService Worker: in Ordnung');
process.exit(fail.length ? 1 : 0);
