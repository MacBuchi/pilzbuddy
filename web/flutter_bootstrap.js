// Eigene Startdatei der Web-App (#387).
//
// Flutter erzeugt diese Datei sonst selbst. Sobald sie hier liegt, nimmt
// der Build sie als Vorlage und ersetzt die drei Platzhalter unten
// (Lader, Build-Konfiguration, Bauversion).
//
// **Die Platzhalter dürfen in KEINEM Kommentar stehen** — auch nicht als
// Beispiel. Der Build ersetzt sie überall in der Datei, und der Lader ist
// mehrzeilig: Aus einer `//`-Zeile bricht er sofort aus, danach ist die
// Datei Syntaxmüll und die App startet gar nicht mehr. Genau so beim Bau
// dieses Features passiert — sichtbar nur als `SyntaxError` in der
// Browser-Konsole.
//
// **Warum wir sie brauchen, und zwar zwingend:** Die erzeugte Fassung
// übergibt dem Loader `serviceWorkerSettings`. Der registriert damit
// `flutter_service_worker.js` — eine 784-Byte-Datei, deren einzige
// Aufgabe es ist, sich selbst wieder abzumelden (Flutters eigener Worker
// ist abgekündigt). Und er tut das genau dann, wenn für diesen Scope
// schon eine Registrierung existiert. Ab dem zweiten Besuch wäre das
// UNSERE — sie würde überschrieben und meldete sich ab. Der Cache wäre
// bei jedem Laden weg, ohne eine einzige Fehlermeldung.
//
// Der Aufruf unten hat deshalb kein `serviceWorkerSettings`, und die
// Versionsnummer aus dem Build wandert stattdessen an unseren Worker.
{{flutter_js}}
{{flutter_build_config}}

// Eigener Einstieg statt des Standardaufrufs: Danach steht fest, was der
// Browser wirklich geholt hat — und genau das bekommt der Worker zu
// sehen. Ohne diesen Schritt läge nach dem ERSTEN Besuch nur die Hülle im
// Cache: Beim ersten Laden kontrolliert der Worker die Seite noch nicht
// (er wird ja gerade erst installiert), er sieht also keine einzige
// Anfrage. Der Offline-Start hinge damit daran, dass jemand die Seite
// zufällig ein zweites Mal öffnet.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    warmServiceWorkerCache();
  },
});

// Eine LISTE statt einer gepflegten Aufzählung im Worker: Welche
// CanvasKit-Variante und welche Schriften nötig sind, entscheidet der
// Browser. Eine Liste von Hand wäre bei jeder Änderung still falsch —
// und „still falsch" heißt hier: startet ohne Netz nicht mehr.
function warmServiceWorkerCache() {
  if (!('serviceWorker' in navigator)) return;
  navigator.serviceWorker.ready
      .then(function (registration) {
        if (!registration.active) return;
        registration.active.postMessage({
          type: 'warm',
          urls: performance.getEntriesByType('resource')
              .map(function (entry) { return entry.name; })
              .filter(function (name) {
                return name.startsWith(self.location.origin);
              }),
        });
      })
      .catch(function () {
        // Kein Worker, kein Vorwärmen — die App läuft trotzdem.
      });
}

// Registriert wird RELATIV, damit der Scope dem `--base-href` folgt:
// `/pilzbuddy/` in der Freigabe, `/pilzbuddy-preview/` in der Vorschau.
// `updateViaCache: 'none'` hält den Worker selbst aus dem HTTP-Cache
// heraus — sonst könnte ausgerechnet die Datei alt bleiben, die alles
// andere aktuell halten soll.
//
// Die Versionsnummer würfelt Flutter je Build neu. Sie ist keine
// Prüfsumme, aber genau das, was hier gebraucht wird: neuer Deploy,
// neuer Worker, neuer Cache. `sw.js` liest sie aus seiner eigenen URL —
// eine Quelle, keine zweite Stelle zum Synchronhalten.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker
        .register('sw.js?v=' + {{flutter_service_worker_version}},
                  {updateViaCache: 'none'})
        .catch(function (error) {
          // Kein Offline-Start ist kein Grund, die App nicht zu starten.
          console.warn('Service Worker nicht registriert:', error);
        });
  });
}
