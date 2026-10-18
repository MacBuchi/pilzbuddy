// Long Tasks der Web-Vorschau in Chrome auf einem Android-Gerät, Wald +
// Höhenlinien an (#689, B2). Vorher/Nachher-Zahlen in
// docs/map-performance.md.
//
//     ADB=<pfad zu adb> node tool/phone_map_bench.mjs <label> [bilder-ordner]
//
// Voraussetzungen: Gerät per USB, Vorschau in Chrome angemeldet,
// `adb shell svc power stayon usb`. Chrome wird je Lauf neu gestartet —
// sonst hängt der DevTools-Socket ab der zweiten Verbindung.
//
// Zwei Fallen, beide beim Bau gefunden: CDP-Touch-Ereignisse erreichen
// MapLibre GL JS auf dem Gerät NICHT (die Karte steht, die Zahlen sehen
// nach „nichts zu tun" aus) — gewischt wird deshalb über
// `adb shell input swipe`.
// Und der Wisch muss im freien Kartenteil beginnen, nicht auf der
// Knopfleiste oder der Legende; die Koordinaten gelten für 1440 × 2560.
// Das Bild nach dem ersten Wisch zeigt, ob die Karte sich bewegt hat.
//
// Die Ebenen werden per localStorage eingeschaltet und bleiben an.
import {execFileSync} from 'node:child_process';
const ADB = process.env.ADB ?? 'adb';
const URL = 'https://macbuchi.github.io/pilzbuddy-preview/';
const label = process.argv[2] ?? 'run';
const shotDir = process.argv[3] ?? '.';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const adb = (...a) => execFileSync(ADB, a, {encoding: 'utf8'});

adb('shell', 'am', 'force-stop', 'com.android.chrome');
await sleep(1500);
adb('shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', URL + '?bench=' + Date.now(), 'com.android.chrome');
adb('forward', 'tcp:9222', 'localabstract:chrome_devtools_remote');
await sleep(4000);
let page;
for (let i = 0; i < 30 && !page; i++) {
  try {
    const t = await (await fetch('http://127.0.0.1:9222/json')).json();
    page = t.find((x) => x.type === 'page' && x.url.includes('pilzbuddy-preview'));
  } catch {}
  if (!page) await sleep(500);
}
if (!page) throw new Error('keine Seite');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const send = (method, params = {}) => new Promise((r) => {
  const i = ++id; pending.set(i, r); ws.send(JSON.stringify({id: i, method, params}));
});
const evaluate = async (expression) =>
  (await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true})).result?.result?.value;

await send('Page.enable');
await send('Runtime.enable');
// Ebenen an — vor dem Neuladen, sonst liest die App den alten Stand.
console.log('vorher:', await evaluate(`JSON.stringify({f: localStorage.getItem('flutter.forest_layer_enabled'), c: localStorage.getItem('flutter.contour_layer_enabled')})`));
await evaluate(`localStorage.setItem('flutter.forest_layer_enabled', 'true'); localStorage.setItem('flutter.contour_layer_enabled', 'true'); 1`);
await send('Page.addScriptToEvaluateOnNewDocument', {source: `
  window.__lt = [];
  new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__lt.push([e.startTime, e.duration]); })
    .observe({type: 'longtask', buffered: true});`});
await send('Page.reload', {ignoreCache: false});
await sleep(3000);
console.log('Zähler da:', await evaluate('Array.isArray(window.__lt)'));
await sleep(57000);
const shot = async (name) => { const r = await send('Page.captureScreenshot', {format: 'png'}); (await import('node:fs')).writeFileSync(shotDir + '/' + label + '-' + name + '.png', Buffer.from(r.result.data, 'base64')); };
await shot('geladen');
const tLoad = await evaluate('performance.now()');
// Fünf lange Wischer (70 % der Breite) nach links, 2,5 s Abstand.
const W = await evaluate('innerWidth'), H = await evaluate('innerHeight');
for (let s = 0; s < 5; s++) {
  // Echte Touch-Eingabe: CDP-Touch erreicht MapLibre GL JS nicht.
  // Abwechselnd hin und zurück, damit die Karte im Gebiet bleibt.
  if (s % 2 === 0)  adb('shell', 'input', 'swipe', '1100', '780', '300', '780', '400');
  else adb('shell', 'input', 'swipe', '300', '840', '1100', '840', '400');
  if (s === 0) await shot('ein-wischer');
  await sleep(4000);
}
await shot('gewischt');
await sleep(10000);
const lt = await evaluate('JSON.stringify(window.__lt)');
const res = await evaluate(`JSON.stringify(performance.getEntriesByType('resource').map(e => e.name).filter(n => /map_worker|main\\.dart\\.(wasm|js)|maplibre-gl/.test(n)))`);
const ver = await evaluate(`document.title`);
const tasks = JSON.parse(lt);
const sum = (a) => a.reduce((s, [, d]) => s + d, 0);
const load = tasks.filter(([t]) => t < tLoad), pan = tasks.filter(([t]) => t >= tLoad);
const fmt = (a) => `${a.length} Tasks, blockiert ${(sum(a) / 1000).toFixed(1)} s, längster ${(Math.max(0, ...a.map(([, d]) => d)) / 1000).toFixed(2)} s`;
console.log(`[${label}] ${ver}`);
console.log(`  Laden (60 s): ${fmt(load)}`);
console.log(`  5 Wischer:    ${fmt(pan)}`);
console.log('  Dateien:', res);
ws.close();
process.exit(0);
