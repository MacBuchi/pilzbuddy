// Der Service Worker der Web-App (#387, Stufe 4 von vier).
//
// Ohne ihn passiert beim Start ohne Netz gar nichts: Der Browser bekommt
// keine `index.html`, also keine App — und damit laufen auch die drei
// Stufen davor ins Leere (Übersichtskarte #383, Spots in IndexedDB #385,
// Ausgangskorb #386). Erst hier ergeben sie zusammen etwas.
//
// **Die tragende Entscheidung: immer zuerst das Netz, der Cache nur als
// Rückfall.** Ein Service Worker, dessen Cache gewinnt, nagelt Nutzer auf
// einen alten Stand — und umgeht damit genau die kontrollierte
// Beförderung, auf der das Release-Modell dieses Projekts beruht. Bei
// `network-first` kann das nicht passieren. Dazu ein harter Grund:
// Flutters Web-Ausgaben tragen KEINE Inhalts-Prüfsummen (`main.dart.js`
// heißt immer gleich), ein `cache-first` lieferte also stillschweigend
// die alte App.
//
// Der Preis ist ehrlich: Diese Datei macht die PWA **nicht schneller**,
// nur startfähig. Genau das war der Auftrag.
//
// **Wenn dieser Worker je kaputt ist**, gibt es drei Wege hinaus:
//   1. Jeder Fehler unten fällt auf ein nacktes `fetch` durch.
//   2. `postMessage({type: 'unregister'})` räumt Registrierung und Cache.
//   3. Der eigentliche: Ein Build ohne die Registrierung in
//      `flutter_bootstrap.js` plus ein `sw.js`, das sich selbst abmeldet,
//      erreicht jeden Online-Nutzer beim nächsten Laden — eben WEIL die
//      Navigation netzwerkzuerst läuft.
'use strict';

// Je Build eine neue Nummer (aus der eigenen URL) und damit ein neuer
// Cache. Ohne `?v=` — etwa beim Aufruf von Hand — bleibt es bei „dev".
const VERSION = new URL(self.location.href).searchParams.get('v') || 'dev';
const CACHE = 'pilzbuddy-' + VERSION;

// Nur die Hülle, und nur was der Start ohne Netz zwingend braucht.
// CanvasKit steht bewusst NICHT hier: Welche Variante geholt wird
// (`canvaskit/` oder `canvaskit/chromium/`), entscheidet der Browser —
// die kommt über den Laufzeit-Cache dazu.
const SHELL = [
  './',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
];

// Schwacher Empfang ist im Wald der Normalfall, und „langsam" ist für den
// Start schlimmer als „aus": Ohne Grenze hinge die App am hängenden Netz,
// statt die Kopie zu nehmen.
const NAVIGATION_TIMEOUT_MS = 3000;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Einzeln und fehlertolerant: `cache.addAll` verwirft ALLES, wenn
    // eine einzige Datei fehlt — eine umbenannte Grafik legte damit den
    // ganzen Offline-Start still.
    await Promise.allSettled(SHELL.map((path) => cache.add(path)));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Jeder Cache außer dem eigenen gehört zu einem früheren Build.
    const names = await caches.keys();
    await Promise.all(
        names.filter((name) => name !== CACHE).map((name) => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  // Nur Lesezugriffe: Ein POST an Supabase hat hier nichts verloren.
  if (request.method !== 'GET') return;
  // Teilanfragen bleiben unangetastet — eine 206 lässt sich nicht in den
  // Cache legen, `cache.put` wirft dabei.
  if (request.headers.has('range')) return;
  // Fremde Ziele (Supabase, DWD, GitHub) nie anfassen: Deren Antworten
  // sind entweder persönlich oder riesig, und ihr Ausfall ist eine
  // Aussage, die die App selbst behandeln muss.
  if (new URL(request.url).origin !== self.location.origin) return;

  event.respondWith(networkFirst(request, request.mode === 'navigate'));
});

async function networkFirst(request, isNavigation) {
  // Der Netz-Versuch legt bei Erfolg selbst ab. Wichtig für den Fall
  // „Zeitlimit gerissen": Die Antwort kommt vielleicht später doch, und
  // dann soll sie wenigstens im Cache landen.
  const fromNetwork = fetchAndCache(request);
  try {
    return await (isNavigation
        ? Promise.race([fromNetwork, rejectAfter(NAVIGATION_TIMEOUT_MS)])
        : fromNetwork);
  } catch (_) {
    const cached = await caches.match(request, {cacheName: CACHE});
    if (cached) return cached;
    // Eine Navigation darf auch dann noch gelingen, wenn genau diese
    // Adresse nie im Cache lag — die App ist eine einzige Seite.
    if (isNavigation) {
      const shell = await caches.match('./', {cacheName: CACHE});
      if (shell) return shell;
    }
    // Nichts da: durchreichen und scheitern wie ohne Worker.
    return fetch(request);
  }
}

async function fetchAndCache(request) {
  const response = await fetch(request);
  // Nur vollständige, erfolgreiche Antworten. Weiterleitungen und Fehler
  // als Kopie zu behalten hieße, sie später ohne Netz zu wiederholen.
  if (response.status === 200) {
    const copy = response.clone();
    caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
  }
  return response;
}

async function warm(urls) {
  const cache = await caches.open(CACHE);
  for (const url of urls) {
    try {
      if (new URL(url).origin !== self.location.origin) continue;
      if (await cache.match(url)) continue;
      const response = await fetch(url);
      if (response.status === 200) await cache.put(url, response);
    } catch (_) {
      // Eine Datei, die sich nicht holen lässt, ist kein Grund
      // aufzuhören — die übrigen sind es wert.
    }
  }
}

function rejectAfter(ms) {
  return new Promise((_, reject) =>
      setTimeout(() => reject(new Error('Zeitlimit')), ms));
}

self.addEventListener('message', (event) => {
  if (!event.data) return;
  // Was die Seite beim ersten Besuch wirklich geholt hat — siehe
  // `flutter_bootstrap.js`. Beim ersten Laden kontrolliert dieser Worker
  // die Seite noch nicht und sieht deshalb keine einzige Anfrage; ohne
  // diesen Nachschlag läge nur die Hülle im Cache.
  if (event.data.type === 'warm' && Array.isArray(event.data.urls)) {
    event.waitUntil(warm(event.data.urls));
    return;
  }
  // Die Notbremse. Aus der Konsole:
  //   navigator.serviceWorker.controller.postMessage({type: 'unregister'})
  if (event.data.type !== 'unregister') return;
  event.waitUntil((async () => {
    try {
      await self.registration.unregister();
    } catch (error) {
      console.warn('Abmelden fehlgeschlagen:', error);
    }
    const names = await caches.keys();
    await Promise.all(names.map((name) => caches.delete(name)));
    // Bewusst OHNE die Seite neu zu laden: Beim nächsten Laden meldet
    // `flutter_bootstrap.js` den Worker sofort wieder an, und dann wäre
    // von der Notbremse nichts mehr zu sehen — auch nicht für den, der
    // gerade prüft, ob sie wirkt. Wer aufgeräumt hat, lädt selbst neu.
  })());
});
