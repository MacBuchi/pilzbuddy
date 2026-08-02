# Änderungen in PilzBuddy

Was sich in welcher Version geändert hat — in Alltagssprache und mit dem
Neuesten zuerst. Dieselbe Liste steht in der App im Profil unter
„Über PilzBuddy" → „Was ist neu".

Die technische Fassung mit allen Einzelheiten liegt in den GitHub-Releases:
https://github.com/MacBuchi/pilzbuddy/releases

## Versionshistorie in der App

*2. August 2026 · Version 1.33.0*

- Diese Liste gibt es jetzt auch in der App: Profil → „Über PilzBuddy" →
  „Was ist neu".
- Sie ist mitgeliefert und braucht keine Verbindung — sie lässt sich also
  auch im Wald nachlesen.

## Die Karte bleibt sichtbar

*26. und 27. Juli 2026 · Versionen 1.29 bis 1.32.1*

Der Schwerpunkt dieser Woche: Die Karte soll nie als graue Fläche dastehen,
und sie soll langes Verschieben und Zoomen überstehen, ohne die App
anzuhalten.

- Wo noch keine Karte geladen ist, liegt jetzt ein Landton statt einer
  grauen Fläche; einmal geladene Bereiche bleiben zwischengespeichert.
- Ohne Empfang und im Offline-Modus liegt eine eingebaute Übersichtskarte
  unter der Karte — statt Leere siehst du Land, Küsten und Grenzen.
- Die Karte geht deutlich sparsamer mit Speicher um. Vorher konnte langes
  Verschieben dazu führen, dass Android die App beendet.
- Beendet sich die App unerwartet, meldet sie beim nächsten Start selbst,
  woran es lag. Vorher blieb so etwas unbemerkt.

**Behoben:** Die Offline-Karte blieb leer, sobald eine Region fertig
heruntergeladen war. Beim Abmelden erschien eine Fehlermeldung, obwohl
nichts schiefgegangen war.

## Konto, Anmeldung und Passwort

*25. und 26. Juli 2026 · Versionen 1.27, 1.28, 1.31.0 und 1.31.1*

Die Anmeldung war der Bereich mit den meisten Sackgassen. Für jeden Fall
gibt es jetzt einen Weg zurück ins Konto.

- Bei der Registrierung bestätigst du deine E-Mail-Adresse mit einem Code
  aus der Mail. Damit gehört die Adresse wirklich zum Konto — wichtig, weil
  die Freundessuche und das Zurücksetzen des Passworts daran hängen.
- „Passwort vergessen" läuft ebenfalls über einen Zahlencode. Der
  funktioniert auch dann, wenn du die Mail auf einem anderen Gerät liest.
- „Passwort ändern" gibt es im Profil; es fragt zur Sicherheit das aktuelle
  Passwort ab.
- Beide Mails lassen sich erneut anfordern, mit 60 Sekunden Wartezeit
  dazwischen.
- Passt eine ältere App-Version nicht mehr zum Server, sagt die App das
  jetzt deutlich, statt mit „Internet verfügbar?" zu scheitern.

## Recht, Lizenz und Konto-Löschung

*20. und 21. Juli 2026 · Versionen 1.22 bis 1.26.0*

- Du kannst dein Konto selbst löschen — sofort, ohne Karenzzeit, in der App
  oder über eine Webseite ohne installierte App.
- Eine Datenschutzerklärung sagt, was gespeichert wird und was davon
  öffentlich ist. Sie ist im Profil verlinkt.
- PilzBuddy steht unter der MIT-Lizenz; die Lizenzen aller verwendeten
  Bausteine stehen im Profil.
- Updates lädt jetzt der Browser herunter und du installierst sie selbst.
  Der eingebaute Installer brauchte dafür Berechtigungen, die eine
  Karten-App nicht haben sollte.
- Fehler, die die App abfängt und übersteht, werden gesammelt. Sonst bleibt
  unbemerkt, was Nutzerinnen und Nutzer stört, ohne dass die App abstürzt.

## Live-Standort teilen

*19. und 20. Juli 2026 · Versionen 1.16 bis 1.21.1*

- Deine eigene Position erscheint als Buddy-Avatar auf der Karte.
- Den Live-Standort kannst du für 1, 2 oder 4 Stunden mit Freunden teilen.
  Die Freigabe endet von selbst und lässt sich jederzeit vorher beenden.
- Unten links steht ein Maßstab, und der Zoom endet dort, wo es keine
  Kartendaten mehr gibt.
- Kartendownloads laufen weiter, wenn du zwischendurch die App wechselst.

**Behoben:** Login- und Registrierungsfelder waren für Passwortmanager
unsichtbar. Die Karte setzte gelegentlich aus. Das Feedback-Banner
verschwand sofort nach dem Absenden. Die Anmeldedaten landeten im
Android-Cloud-Backup.

## Import und Export

*19. Juli 2026 · Versionen 1.15 bis 1.16.1*

- GPX-, KML- und KMZ-Dateien aus anderen Karten-Apps importieren; jeder
  Punkt wird einzeln zu einem Spot, den du vorher noch anpassen kannst.
- Eigene Spots samt Fundhistorie als GPX exportieren.
- Art und Funddatum werden aus dem Wegpunkt vorbelegt, soweit sie sich
  daraus erkennen lassen.

**Behoben:** GPX- und KML-Dateien waren im Android-Dateidialog ausgegraut
und ließen sich nicht auswählen.

## Offline-Karten

*19. Juli 2026 · Versionen 1.10 bis 1.13.2 · nur Android*

- Karten einzelner Bundesländer im Profil herunterladen. Ohne Empfang
  schaltet die App von selbst darauf um.
- Große Downloads lassen sich fortsetzen und laufen weiter, wenn du in der
  App woanders hin wechselst.
- Heruntergeladene Karten werden gegen eine Prüfsumme geprüft, damit keine
  halbe Datei als fertig gilt.
- Eine Übersichtskarte für Deutschland, Österreich und die Schweiz ist
  eingebaut. Auch ohne heruntergeladene Region siehst du damit Land statt
  einer grauen Fläche.
- Bricht die Verbindung unterwegs ab, gibt der Download nicht mehr auf,
  sondern nimmt den Faden von selbst wieder auf.

**Behoben:** Der Offline-Karte fehlten die Beschriftungen und die Farben
für Wald, Wasser und Siedlung.

## Pilz-Icons, Avatare und App-Icon

*18. bis 25. Juli 2026 · Versionen 1.2.1 bis 1.26.4*

- Die Marker zeigen die Pilzgruppe, statt nur „essbar" oder „giftig" zu
  behaupten. PilzBuddy bestimmt keine Pilze.
- Eigene Zeichnungen für Pfifferling, Totentrompete, Milchlinge und
  Maronen-Röhrling.
- Für das Profil lässt sich ein Pilz-Avatar auswählen.
- Das App-Icon zeigt die Buddies groß, statt sie klein in der Mitte
  verschwinden zu lassen.

**Behoben:** In den Listen fehlten die Arten-Icons, und Stiel und
Kartenansicht waren falsch gezeichnet. Das Diagramm „Funde pro Jahr" hatte
eine unlesbare Achse.

## Rückmeldungen direkt aus der App

*18. und 19. Juli 2026 · Versionen 1.4 bis 1.9.5*

- Wunsch, Fehler oder eine fehlende Pilzart direkt aus der App melden.
  Daraus entsteht automatisch ein Eintrag im öffentlichen Projekt — ein
  Hinweis im Dialog sagt das vorher deutlich.
- Die Android-App weist auf neue Versionen hin.
- Auf Wunsch aufgenommen: Violetter Lacktrichterling.
- Die Daten deiner Freunde aktualisieren sich von selbst. Bei fremden Spots
  steht, wer sie gefunden hat, und die Farbe zeigt, wem ein Spot gehört.

**Behoben:** Die Karte ließ sich versehentlich verdrehen — die Drehgeste
ist abgeschaltet. Ein Update konnte die App nach dem Herunterladen zum
Absturz bringen.

## Der Anfang

*18. Juli 2026 · Versionen 1.0 bis 1.3*

- Pilz-Spots auf der Karte festhalten: Position über ein Fadenkreuz statt
  mit dem Finger zielen, dazu Art, Anzahl, Funddatum und eine Notiz.
- Auswahl bekannter Pilzarten mit Kategorien und passenden Icons.
- Freunde einladen und Spots mit ihnen teilen.
- Animierte Buddies auf dem Anmeldebildschirm.

## Unter der Haube

Nicht jede Version bringt etwas Sichtbares. Dazwischen liegt das, was man
erst bemerkt, wenn es fehlt: ein wöchentliches verschlüsseltes Backup der
Datenbank, automatische Tests vor jeder Veröffentlichung, ein Abgleich
zwischen App und Datenbank, der falsche Änderungen vor der Auslieferung
stoppt, und eine wöchentliche Zusammenfassung aller Fehler, die die App
abgefangen hat.
