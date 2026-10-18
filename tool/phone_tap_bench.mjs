// Wie schnell antwortet die Web-App auf einen Tipp, während sie lädt?
// (#689, B3). Gemessen wird, was ein Mensch merkt: ab dem Neuladen alle
// 500 ms ein Tipp in den freien Kartenteil, 15 s lang, danach fünf Tipps
// in Ruhe als Vergleich. Jeder Tipp ist eine echte Berührung
// (`adb shell input tap` — CDP-Touch erreicht MapLibre GL JS auf dem Gerät
// nicht, siehe phone_map_bench.mjs), seine Antwortzeit liest die Seite
// selbst über die Event-Timing-API: vom Fingerdruck bis zum nächsten
// gemalten Bild, also Wartezeit + Verarbeitung + Malen.
//
//     ADB=<pfad zu adb> node tool/phone_tap_bench.mjs <label>
//
// Voraussetzungen wie phone_map_bench.mjs (Gerät per USB, Vorschau in
// Chrome angemeldet, `adb shell svc power stayon usb`). BENCH_URL setzt
// eine andere Adresse (lokaler Build über `adb reverse`), BENCH_STORAGE
// eine JSON-Datei mit localStorage-Einträgen, die vor dem Neuladen
// gesetzt werden (die Anmeldung hängt am Origin).
//
// Die Event-Timing-API meldet nur Ereignisse ab 16 ms. Ein Tipp ohne
// Eintrag war also schneller; gezählt wird er über einen eigenen
// pointerdown-Zähler, sonst sähe „alles schnell" aus wie „nichts
// getippt". Die Bildschirmlage des Tipps wird zu Beginn geeicht (ein
// Tipp, die Seite meldet, wo er ankam) — Status- und Adressleiste sind je
// Gerät verschieden hoch.
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
const ADB = process.env.ADB ?? 'adb';
const URL = process.env.BENCH_URL ?? 'https://macbuchi.github.io/pilzbuddy-preview/';
const STORAGE = process.env.BENCH_STORAGE;
const label = process.argv[2] ?? 'run';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const adb = (...a) => execFileSync(ADB, a, {encoding: 'utf8'});
const host = new globalThis.URL(URL).host;

adb('shell', 'am', 'force-stop', 'com.android.chrome');
await sleep(1500);
adb('shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', URL + '?bench=' + Date.now(), 'com.android.chrome');
adb('forward', 'tcp:9222', 'localabstract:chrome_devtools_remote');
await sleep(4000);
let page;
for (let i = 0; i < 30 && !page; i++) {
  try {
    const t = await (await fetch('http://127.0.0.1:9222/json')).json();
    page = t.find((x) => x.type === 'page' && x.url.includes(host));
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
// Auf der geladenen Seite warten, bis sie Berührungen annimmt, dann eichen.
await sleep(20000);
if (STORAGE) {
  const o = JSON.parse(readFileSync(STORAGE, 'utf8'));
  await evaluate(`(()=>{const o=${JSON.stringify(o)}; for (const k in o) localStorage.setItem(k,o[k]); return 1})()`);
}
await evaluate(`localStorage.setItem('flutter.forest_layer_enabled', 'true'); localStorage.setItem('flutter.contour_layer_enabled', 'true'); 1`);
const W = await evaluate('innerWidth'), H = await evaluate('innerHeight'), dpr = await evaluate('devicePixelRatio');
// Freier Kartenteil: links, unter dem Erinnerungsbanner, über der Legende.
const cx = Math.round(W * 0.1), cy = Math.round(H * 0.3);
await evaluate(`window.__cal = null; addEventListener('pointerdown', (e) => { window.__cal = [e.clientX, e.clientY]; }, {capture: true, once: true}); 1`);
const guessX = Math.round(cx * dpr), guessY = Math.round(cy * dpr);
adb('shell', 'input', 'tap', String(guessX), String(guessY));
await sleep(1500);
const cal = await evaluate('JSON.stringify(window.__cal)');
if (!cal || cal === 'null') throw new Error('Eichtipp kam nicht an');
const [gx, gy] = JSON.parse(cal);
const tapX = String(Math.round(guessX + (cx - gx) * dpr));
const tapY = String(Math.round(guessY + (cy - gy) * dpr));

await send('Page.addScriptToEvaluateOnNewDocument', {source: `
  window.__ev = []; window.__downs = [];
  addEventListener('pointerdown', (e) => window.__downs.push(e.timeStamp), {capture: true});
  new PerformanceObserver((l) => { for (const e of l.getEntries()) {
    if (e.interactionId) window.__ev.push([e.interactionId, e.name, e.startTime, e.duration, e.processingStart - e.startTime]);
  } }).observe({type: 'event', durationThreshold: 16, buffered: true});`});
await send('Page.reload', {ignoreCache: false});
// Ab dem Neuladen: 15 s lang alle 500 ms ein Tipp.
const t0 = Date.now();
await sleep(500);
while (Date.now() - t0 < 15500) {
  adb('shell', 'input', 'tap', tapX, tapY);
  await sleep(500 - ((Date.now() - t0) % 500));
}
await sleep(30000);
for (let i = 0; i < 5; i++) { adb('shell', 'input', 'tap', tapX, tapY); await sleep(1000); }
await sleep(2000);
const ev = JSON.parse(await evaluate('JSON.stringify(window.__ev)'));
const downs = JSON.parse(await evaluate('JSON.stringify(window.__downs)'));
const ver = await evaluate('document.title');
// Je Tipp die längste Antwort: pointerdown und pointerup tragen eigene
// interactionIds, gehören aber zu EINEM Fingerdruck — alles, was binnen
// 300 ms nach dem ersten Eintrag beginnt, zählt zu ihm.
const taps = [];
for (const [, , start, dur, delay] of ev.sort((a, b) => a[2] - b[2])) {
  const last = taps[taps.length - 1];
  if (last && start - last.start < 300) {
    last.dur = Math.max(last.dur, dur); last.delay = Math.max(last.delay, delay);
  } else taps.push({start, dur, delay});
}
const restFrom = downs.length >= 5 ? downs[downs.length - 5] - 1 : Infinity;
const load = taps.filter((t) => t.start < restFrom), rest = taps.filter((t) => t.start >= restFrom);
const loadDowns = downs.filter((d) => d < restFrom).length;
const med = (a, k) => { const v = a.map((t) => t[k]).sort((x, y) => x - y); return v.length ? Math.round(v[Math.floor(v.length / 2)]) : 0; };
const max = (a, k) => Math.round(Math.max(0, ...a.map((t) => t[k])));
// Antwort = Wartezeit + Verarbeitung + Malen; Wartezeit = so lange lag
// der Tipp, weil der Hauptthread anderes tat. Gezählt über 16 ms.
const fmt = (a, n) => `${n} Tipps · Antwort ≥ 100 ms: ${a.filter((t) => t.dur >= 100).length}, ≥ 300 ms: ${a.filter((t) => t.dur >= 300).length}, Median ${med(a, 'dur')}, längste ${max(a, 'dur')} ms · Wartezeit ≥ 50 ms: ${a.filter((t) => t.delay >= 50).length}, längste ${max(a, 'delay')} ms`;
console.log(`[${label}] ${ver}  (Tipp bei ${tapX},${tapY} px)`);
console.log(`  beim Laden (15 s): ${fmt(load, loadDowns)}`);
console.log(`  in Ruhe:           ${fmt(rest, downs.length - loadDowns)}`);
console.log('  Verlauf beim Laden (s: Antwort/Wartezeit ms):', load.map((t) => `${(t.start / 1000).toFixed(1)}: ${t.dur}/${Math.round(t.delay)}`).join(' · '));
ws.close();
process.exit(0);
