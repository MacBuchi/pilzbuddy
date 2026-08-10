# Änderungen in PilzBuddy

Was sich in welcher Version geändert hat — in Alltagssprache und mit dem
Neuesten zuerst. Dieselbe Liste steht in der App im Profil unter
„Über PilzBuddy" → „Was ist neu".

Die technische Fassung mit allen Einzelheiten liegt in den GitHub-Releases:
https://github.com/MacBuchi/pilzbuddy/releases

## Funde ohne Empfang gehen nicht mehr verloren

*10. August 2026 · Version 1.79.0*

Bisher brauchte das Eintragen eines Fundes eine Verbindung. Ausgerechnet
im Wald gibt es die selten — wer dort einen Spot anlegte, bekam „Keine
Verbindung" und musste sich den Fund merken, bis er zu Hause war.

Ab jetzt landet ein Fund ohne Empfang in einem **Ausgangskorb** auf
deinem Gerät und geht von allein raus, sobald du wieder Netz hast.

- Der wartende Spot erscheint sofort auf der Karte — blasser und mit
  einer kleinen Uhr. Du siehst also, wo du schon warst, und legst
  denselben Spot nicht zweimal an.
- Oben zeigt ein Hinweis, wie viele Einträge noch warten. Antippen
  versucht es sofort.
- Gesendet wird außerdem beim Start der App und sobald die Verbindung
  zurückkommt — meist musst du gar nichts tun.
- Wartende Einträge zählen ganz normal mit: in der Statistik, in der
  Pilzampel und beim Export. Sie sind ja passiert. Nur ändern lassen sie
  sich erst, wenn sie übertragen sind.
- Ein wartender Eintrag lässt sich verwerfen, falls du ihn doch nicht
  willst. Und wenn du dich abmeldest, während noch etwas wartet, fragt
  die App vorher nach.

Was der Server nicht annimmt, verschwindet nicht still: Solche Einträge
werden gesondert gemeldet, mit dem Grund.

## Die feine Waldkarte am Stück laden

*10. August 2026 · Version 1.78.0*

Die Waldtypen-Ebene kann seit kurzem feiner hinsehen: Waben von etwa
100 Metern statt 250. Diese feinen Daten hat die App bisher unterwegs
nachgeladen — also ausgerechnet dort, wo im Wald selten Empfang ist.

Unter „Offline-Karten" steht jetzt ein Eintrag **Feine Waldkarte**, der
alles auf einmal holt: rund 26 MB für Deutschland, Österreich und die
Schweiz. Einmal zu Hause im WLAN antippen, und die feine Stufe ist
draußen da.

- Der Eintrag zeigt, wie viel schon auf dem Gerät liegt.
- Anhalten geht jederzeit; was geladen ist, bleibt, und der Rest lässt
  sich später nachholen.
- Wird der Platz knapp, löschst du die feinen Daten wieder — die Karte
  zeigt dann weiter die eingebaute Fassung mit den größeren Waben.

## Updates kommen jetzt gebündelt

*10. August 2026 · Version 1.77.0*

Bisher hat jede einzelne Änderung sofort ein Update ausgelöst — an einem
fleißigen Tag waren das acht Hinweise für dieselbe App. Ab jetzt sammeln
sich die Änderungen, und ein Update erscheint erst, wenn ein Stand
bewusst freigegeben wird. Der Hinweis in der App kommt dann einmal, mit
allem, was seit dem letzten Mal dazugekommen ist.

Für dich ändert sich sonst nichts: Was du installiert hast, läuft weiter,
und die Web-Version zeigt denselben freigegebenen Stand wie die App.

## Die Pilzampel leuchtet jetzt IM Wald

*10. August 2026 · Version 1.76.0*

Die eigentliche Frage beim Losfahren ist ja nicht „wo ist Wald" und auch
nicht „wo ist gutes Wetter", sondern **wo ist beides**. Genau das zeigt
die Karte jetzt: Der Schalter „Pilzwetter-Ampel" färbt keine eigene
Fläche mehr über Felder und Städte, sondern lässt die **Waldwaben
leuchten**, wo das Wetter gerade mitspielt — hell bei „verhalten",
kräftig bei „günstig", in der Farbe deiner Wahl. Der übrige Wald bleibt
sichtbar, nur zurückgenommen; sonst hätten die leuchtenden Waben keinen
Zusammenhang, in dem man sie liest.

Das ist zugleich eine Vereinfachung: Es gibt nur noch **einen** Schalter
statt zweier Flächen, die sich gegenseitig ausschließen mussten. Und weil
alles in einem Bild entsteht, liegt nichts mehr übereinander.

- Es sind weiterhin **keine Spots von irgendwem** im Spiel — nur dein
  Gerät, das Waldgitter und die Wetterdaten.
- Waldwetter gibt es nur für Deutschland. Außerhalb bleibt der Wald
  normal eingefärbt; „leuchtet nicht" heißt dort also weder schlecht
  noch unbekannt.
- Die Klassen-Auswahl gilt weiter: Wer nur Nadelwald einblendet, sieht
  auch nur Nadelwald leuchten.
- Der Ampel-Schalter schaltet die Waldebene mit ein, und wer die
  Waldebene abschaltet, nimmt die Ampel mit — sie ist ja die Waldkarte
  in anderen Farben.

## Die Pilzampel bekommt eigene Farben

*9. August 2026 · Version 1.75.0*

Die Ampel-Fläche malte bisher in denselben Grün- und Ockertönen wie die
Waldkarte — und die will man ja gerade zusammen sehen. Über Laubwald war
„verhalten" praktisch nicht mehr zu erkennen.

Jetzt bricht die Ampel aus den Erdtönen aus, und **du wählst die Farbe**:
Im Regen-Blatt stehen unter dem Ampel-Schalter drei Familien zur Wahl —
**Violett**, **Magenta** und **Türkis**. Die Wahl gilt für die Fläche auf
der Karte, den Punkt im Spot-Blatt und die Legende, und sie bleibt
gespeichert. Violett ist voreingestellt: Es ist der einzige Ton, der weder
in der Karte (Wasser, Wald, Wege) noch in der Waldebene vorkommt.

## Die Waldkarte bleibt beim Rauszoomen stehen

*9. August 2026 · Version 1.74.0*

Die Waben der Waldkarte verschwanden beim Rauszoomen: erst Lücken, dann
Streifen, und in der Deutschland-Übersicht war gar nichts mehr zu sehen.
Grund war der Zeichner — Waben, die kleiner als ein Bildpunkt wurden,
fielen beim Runden einfach heraus.

Jetzt zählt jede Wabe mit der Fläche, die sie bedeckt. Damit stimmt die
Karte auf jeder Zoomstufe: In der Übersicht sind Harz, Thüringer Wald,
Bayerischer Wald und die Alpen wieder als das zu erkennen, was sie sind,
und beim Hineinzoomen wachsen daraus dieselben scharfen Waben wie bisher.
Nebenbei laufen Wabenränder jetzt weich aus statt zu treppen, und
zwischen gleichfarbigen Nachbarn ist keine helle Naht mehr.

Und die Karte färbt schneller ein — das Zusammenpacken der Bilder war
dreimal so aufwendig eingestellt, wie es sein musste. Das merkt man auch
bei den Regen- und Ampel-Flächen.

**Weniger Datenverbrauch bei den feinen Waben:** Die nachladbaren
100-m-Waben kommen jetzt erst nah dran — etwa ab Maßstab 1 km, wo man
sie auch wirklich sieht. Wer mit eingeschalteter Feinstufe auf
Deutschland herauszoomte, lud bisher nach und nach das ganze Gebiet
nach (26 MB) für ein Bild, das von der eingebauten Karte nicht zu
unterscheiden war.

## Zum Ausprobieren: die Pilzwetter-Ampel

*9. August 2026 · Versionen 1.72.0 und 1.73.0*

**Neu in 1.73.0 — die Ampel auf der Karte:** Im Regen-Blatt gibt es
(bei eingeschalteter Vorschau) den Schalter „Pilzwetter-Ampel". Er
färbt auf der Karte ein, wo die Wetter-Bedingungen für Steinpilz & Co.
gerade **günstig** (grün) oder **verhalten** (ocker) sind — ungünstige
Gegenden bleiben ungefärbt. Zusammen mit der Waldkarte beantwortet das
die Frage „wo könnte ich noch sammeln?": Wald einblenden, Ampel
einblenden, hin. Es werden dabei **keine Spots von irgendwem**
benutzt oder gezeigt — die Fläche ist reines Wetter, gerechnet auf
deinem Gerät, nur für Deutschland. Eine Regenfläche und die Ampel
schließen sich gegenseitig aus (beides übereinander wäre unlesbar).

Im Profil gibt es einen neuen Schalter: **„Pilzwetter-Ampel
(experimentell)"**. Eingeschaltet zeigt das Spot-Blatt (und „Was ist
hier?") eine Einschätzung in Worten — **ungünstig, verhalten oder
günstig** —, gerechnet aus dem Regen der letzten 26 Tage und der
Temperatur der letzten 20 Tage, direkt auf deinem Gerät.

- **Ehrlich bleibt sie:** Die Ampel bewertet die Wetter-**Bedingungen**,
  nicht ob Pilze dastehen. Sie gilt nur für die sechs Arten, an denen
  das Modell gerade geprüft wird (Steinpilz & Co.) — für alle anderen
  sagt sie bewusst nichts. Und sie ist **unvalidiert**: Die Prüfung an
  echten Funden läuft noch; fällt sie durch, verschwindet die Vorschau
  wieder.
- Daneben stehen die Fakten wie bisher: Regen, Temperatur und die
  Saison der Art — die Saison fließt nicht in die Stufe ein.
- Das Wetterdiagramm zeigt weiterhin 14 Tage; die zusätzlichen Tage
  für die Ampel kommen mit den nächsten Daten-Updates automatisch
  (die erste Wetter-Ladung wächst dadurch auf knapp 2 MB).

## Die Waldkarte kann feiner — wenn du willst

*9. August 2026 · Version 1.71.0*

Im Waldtypen-Blatt gibt es einen neuen Schalter: **„Feine Waben
(≈ 100 m) nachladen"**. Eingeschaltet holt die App für das sichtbare
Gebiet eine deutlich feinere Waldkarte aus dem Netz — je Gebiet rund
1 MB, einmal geladen bleibt es auf dem Gerät. Auch „Wald hier" im
Spot-Blatt, der Laubfaktor am Fadenkreuz und „Was ist hier?" rechnen
dann auf den feinen Waben.

- Ohne den Schalter ändert sich nichts: Die eingebaute 250-m-Karte
  bleibt und funktioniert wie bisher ganz ohne Empfang. Fehlt unterwegs
  das Netz, springt sie auch bei eingeschaltetem Schalter still ein.
- Die feine Karte ist nicht nur schärfer, sondern ehrlicher: Bei 250 m
  macht schon eine Baumreihe die ganze Wabe zu „Wald" — auf 100 m
  schrumpft der Waldanteil von 48 auf ehrliche 44 Prozent. Werte können
  sich also leicht ändern; das ist die feinere Messung, keine neuen
  Daten.
- Die feinen Karten werden zentral gepflegt und beim vierteljährlichen
  Daten-Update automatisch erneuert — dafür ist kein App-Update nötig.

## Die Waldkarte hat jetzt Waben

*9. August 2026 · Version 1.70.0*

Die Waldtypen liegen jetzt als **Sechseck-Waben** auf der Karte statt als
Quadrate — organischer anzusehen, und zwar ehrlich: Die Waben sind nicht
bloß aufgemalt, sondern werden direkt aus den 10-Meter-Satellitendaten
berechnet. Jede Wabe deckt dieselbe Fläche ab wie vorher ein Quadrat
(≈ 250 m), die App wird dadurch nicht größer und nicht langsamer —
nachgemessen, bevor es gebaut wurde.

Auch „Wald hier" im Spot-Blatt und der Laubfaktor rechnen jetzt auf den
Waben. An Bestandsgrenzen kann sich dadurch ein Wert leicht ändern —
das ist die neue Zellform, keine neuen Daten (Stand weiterhin 2024).

## Die Waldkarte wird beim Heranzoomen scharf

*9. August 2026 · Version 1.69.0*

Die Waldtypen-Fläche wird jetzt nur noch für den sichtbaren
Kartenausschnitt gezeichnet statt für ganz DACH auf einmal. Für dich
heißt das: Beim Heranzoomen werden die Kacheln **schärfer** statt
verwaschener, und die App braucht dabei nur noch einen Bruchteil des
Speichers. Beim Schieben bleibt alles flüssig — neu gezeichnet wird
erst, wenn du den vorbereiteten Bereich wirklich verlässt.

## Die Waldfarben lagen daneben — jetzt sitzen sie

*9. August 2026 · Version 1.68.1*

Aufmerksamen Augen ist aufgefallen: Am Brocken malte die Karte Laubwald,
wo die Zahlen völlig richtig „reiner Nadelwald" sagten. Die eingefärbte
Waldfläche lag je nach Gegend bis zu 26 Kilometer zu weit südlich — ein
Projektionsfehler beim Zeichnen, der seit Einführung der Ebene bestand.
Alle Zahlen (Laubfaktor, „Wald hier", Legende) waren davon nie betroffen;
nur die Farben auf der Karte saßen verschoben. Danke für den Hinweis!

## „Was ist hier?" — für jede Stelle, nicht nur für deine Spots

*9. August 2026 · Version 1.68.0*

Regen, Temperatur und Waldtyp gab es bisher nur dort, wo schon ein Spot
liegt — also nur für Stellen, an denen du warst. Zum Erkunden brauchst du
es genau andersherum.

Tipp jetzt auf die kleine Legende links unten auf der Karte: Ein Blatt
zeigt für die Stelle unter dem Fadenkreuz den Waldtyp, den Laubfaktor im
Kilometer ringsum, den Regenverlauf der letzten Wochen und die
Temperaturkurve — dieselben Angaben wie im Spot-Blatt.

Das kostet keine Daten: Alle Werte stammen aus den Gittern, die ohnehin
schon auf dem Gerät liegen. Deine Position und die betrachtete Stelle
verlassen das Handy nicht, und im Funkloch steht dort dasselbe wie
zu Hause.

## Der Laubfaktor misst jetzt einen Kilometer

*9. August 2026 · Version 1.67.0*

Der Wert in der Wald-Legende schaute bisher nur 200 Meter weit um das
Fadenkreuz — bei Kacheln von rund 250 Metern Kantenlänge war der Umkreis
also kleiner als ein einziges Kästchen. Herausgekommen sind vier bis sechs
Kästchen, und der Wert sprang beim Schieben der Karte.

Jetzt zählt der Kilometer ringsum, also rund 70 Kästchen. Die Legende
schreibt die Reichweite dazu, damit klar ist, worüber die Zahl redet.

## Funde lassen sich korrigieren

*8. August 2026 · Version 1.66.0*

Vertippt, falsches Datum, zweimal dasselbe eingetragen? Tipp im Spot-Blatt
einfach den Eintrag an: Art, Anzahl, Datum und Notiz lassen sich ändern —
oder der Eintrag verschwindet einzeln, ohne dass der ganze Spot mit seiner
Historie dran glauben muss. Das gilt auch für „Nichts gefunden"-Einträge;
dort lassen sich Datum und Notiz richtigstellen.

Was Pilzfreunde an deinen Spots eingetragen haben, bleibt unangetastet —
ihre Funde gehören ihnen.

## „Hier warst du letztes Jahr erfolgreich"

*8. August 2026 · Version 1.65.0*

Die Karte erinnert dich jetzt an deine eigenen guten Tage: Hattest du an
einem Spot **um diese Jahreszeit** in einem früheren Jahr Erfolg,
erscheint oben ein grüner Hinweis — mit Ort, Art und Jahr. Antippen
öffnet den Spot.

Das ist keine Vorhersage, sondern deine eigene Geschichte: gerechnet
allein aus deinen Funden, ohne Netz, auch tief im Wald. Das X blendet
den Hinweis für die nächsten zwei Wochen aus — die Erinnerung des
nächsten Zeitfensters kommt dann wieder.

## Die Legende misst jetzt mit

*8. August 2026 · Version 1.64.0*

Die Legende zeigt jetzt die Werte an der Stelle des Fadenkreuzes — als
Strich direkt auf ihren Skalen, sobald die Karte zum Stehen kommt:

- **Regen:** Bei den Summen-Ebenen steht der Millimeterwert der
  Kartenmitte im Titel, und ein Strich markiert ihn auf der Farbskala.
- **Wald:** Die Waldtypen-Legende ist zu einer Skala von Laub bis Nadel
  geworden. Ein Strich zeigt den **Laubfaktor** im 200-m-Umkreis des
  Fadenkreuzes (1 = reiner Laubwald, 0 = reiner Nadelwald — Mischwald
  zählt anteilig), daneben steht, wie viel der Umgebung überhaupt Wald
  ist. So siehst du beim Verschieben der Karte sofort, ob sich die
  Fahrt in dieses Waldstück lohnt.

Gerechnet wird bewusst erst, wenn die Karte stillsteht — das Schieben
selbst bleibt flüssig.

## Wald und Regen zusammen, klarere Farben, Legende auf der Karte

*8. August 2026 · Version 1.63.0*

Gleich drei Wünsche aus dem Feld in einem Update:

- **Neue Waldfarben:** Laubwald ist jetzt herbst-ocker, Mischwald
  gelbgrün, Nadelwald dunkel blaugrün — die drei sind endlich auf einen
  Blick zu unterscheiden.
- **Waldklassen einzeln schaltbar:** Im Waldtypen-Blatt gibt es drei
  Häkchen. Wer nur wissen will, wo Laubwald steht, blendet den Rest aus.
- **Regen und Wald gleichzeitig:** Die beiden Ebenen schließen sich
  nicht mehr aus. Der Regen liegt über dem Wald — und wer es übersichtlich
  mag, lässt vom Wald nur die eine Klasse stehen, die ihn interessiert.
- **Legende auf der Karte:** Solange eine Ebene aktiv ist, liegt ihre
  Legende klein links unten auf der Karte. Das X daran merkt sich das
  Ausblenden; zurück geht es im Ebenen-Blatt über „Legende in Karte
  anzeigen".

## Ebene aus heißt jetzt sofort aus

*8. August 2026 · Version 1.62.2*

Wer die Wald- oder Regenebene abgeschaltet hat, sah sie trotzdem noch —
bis zur nächsten Kartenbewegung. Jetzt verschwindet die Fläche in dem
Moment, in dem du den Schalter umlegst. Danke für die schnelle
Rückmeldung aus dem Feld!

## Welcher Wald ist das? Die Karte weiß es jetzt

*8. August 2026 · Versionen 1.62.0 und 1.62.1 (1.62.1: nur aktualisierte Bibliotheken, nichts Sichtbares)*

Wer Sommersteinpilze sucht, will nicht im reinsten Fichtenforst landen.
Die Karte hat dafür einen neuen Knopf: **Waldtypen** färbt den Wald in
drei Grüntönen ein — hell für Laub, mittel für Misch, dunkel für Nadel.
Die Daten kommen aus dem Copernicus-Satellitenprogramm der EU, decken
Deutschland, Österreich und die Schweiz ab und sind aktuell genug, dass
die Käferflächen der letzten Jahre nicht mehr als Fichtenwald auftauchen.

Im Spot-Blatt steht dazu eine neue Zeile: **„Wald hier"** nennt den
Waldtyp an der Stelle, samt Nadelanteil in Prozent. Beides funktioniert
komplett **offline** — die Waldkarte steckt in der App, es wird nichts
geladen und nichts gesendet.

Ehrlich gesagt dazu: Das Raster ist 250 m grob. Es zeigt dir, in welche
Richtung sich die Fahrt lohnt — den einzelnen Buchenhang im Fichtenwald
zeigt es nicht. Regen- und Waldebene wechseln sich ab, weil beide
halbtransparent sind und übereinander nichts mehr zu lesen wäre.

## Vollständige Lizenzangaben

*7. August 2026 · Version 1.61.1*

Die Seite „Open-Source-Lizenzen" im Profil nennt jetzt auch die
**Kartenschrift** und die **Regendaten**. Beide waren längst in der App,
standen dort aber nicht — bei der Schrift fehlte sogar der Lizenztext
selbst, obwohl ihre Lizenz genau den verlangt.

Für dich ändert sich am Verhalten der App nichts. Es ist trotzdem kein
Schönheitsfehler gewesen: Kartendaten, Wetterdaten und Schriften dürfen wir
nur unter der Bedingung verwenden, dass wir ihre Herkunft nennen.

## Fundorte stapeln sich nicht mehr

*6. August 2026 · Version 1.61.0*

Gehst du fünf Meter weiter und trägst den nächsten Pilz ein, entstand
bisher ein **zweiter Fundort** — auf der Karte liegen die Marker dann
übereinander, obwohl es im Wald dieselbe Stelle ist.

Jetzt fragt die App nach: Liegt in **20 m** schon einer deiner Spots,
kannst du den Fund **dort eintragen** statt einen neuen anzulegen. Willst
du trotzdem einen zweiten, geht das mit einem Tipp daneben — die
Entscheidung bleibt bei dir, die App legt nichts still zusammen.

Für das, was sich schon gestapelt hat, gibt es im Profil einen neuen
Punkt: **„Dicht beieinander"**. Er erscheint nur, wenn es wirklich etwas
zu tun gibt, listet die betroffenen Paare mit ihrem Abstand und führt sie
auf Wunsch zusammen — du sagst, welcher Name bleibt.

Ein Fall bleibt außen vor, und zwar mit Absicht: Hat ein Pilz-Buddy an
einem der beiden Spots eingetragen, wird das Paar nicht angeboten. Seine
Funde könnten nicht mitwandern und gingen beim Zusammenführen verloren.

## Kein versehentlicher Sprung mehr auf der Karte

*6. August 2026 · Version 1.60.0*

Langes Draufhalten setzte das Fadenkreuz auf die gedrückte Stelle **und**
zoomte weit heran. Das löste zu leicht aus: Aus der Übersicht landete man
plötzlich woanders und viel zu nah dran, und der Weg zurück war
rauszoomen und wiederfinden. **Ab jetzt ist die Geste aus.**

Zum Heranzoomen genügt ein **Doppeltipp** auf die Stelle — das konnte die
Karte schon immer, es ging nur unter. Das Fadenkreuz stellst du wie bisher
durchs Schieben ein.

Wer die alte Bedienung mochte, holt sie im Profil unter **„Karte gedrückt
halten"** zurück; dann arbeitet sie wieder genau wie vorher.

## Zwei Pilze sehen richtiger aus, das Wetter liest sich leichter

*6. August 2026 · Version 1.59.0*

Der **Steinpilz** hat jetzt den dicken, bauchigen Stiel, den er in echt
auch hat — damit ist er auf der Karte nicht mehr mit der Marone zu
verwechseln. Der **Samtfußrübling** war bisher grau und sah aus wie
irgendein Blätterpilz; er ist jetzt honig-orange und steht auf einem
dünnen dunklen Stiel, genau wie im Winterwald am Totholz.

Im Diagramm unter „Wetter an diesem Spot" liegen jetzt **feine
Hilfslinien** auf Höhe der Gradzahlen. Du musst einen Punkt der
Temperaturkurve nicht mehr quer durchs Bild bis zur Achse verfolgen, um
ihn abzulesen. Die gestrichelte Frostlinie bei 0 °C bleibt dabei die
auffälligste — sie ist im Herbst die Zahl, auf die es ankommt.

## Mehrere Arten auf einmal — und „nichts gefunden"

*6. August 2026 · Version 1.58.0*

Standen an einem Spot Steinpilze **und** Maronen, musstest du das Blatt
bisher zweimal ausfüllen. Jetzt legst du mit **„weitere Art"** die
fertige Zeile ab und tippst gleich die nächste; Datum und Notiz gelten
für alle. Trägst du nur eine Art ein, ändert sich für dich nichts —
„Speichern" nimmt die offene Zeile ohnehin mit.

Neu daneben: **„Nichts gefunden"**. Warst du an einem Spot und stand
dort nichts, kannst du das jetzt festhalten — mit Datum und wenn du
magst einer Notiz, mehr fragt die App nicht. Solche Einträge zählen
**nirgends als Fund**: Deine Statistik bleibt, wie sie ist, das
Pilz-Bild auf der Karte auch, und der Artfilter zeigt den Spot weiterhin
unter der Art, die dort mal stand.

Warum es das gibt: Die App kennt bisher nur Erfolge. Für eine ehrliche
Wachstums-Vorhersage fehlt genau die andere Hälfte — „war da, war
nichts". Ohne sie lässt sich nie prüfen, ob eine Vorhersage stimmt.
Deine Buddys sehen solche Einträge an geteilten Spots übrigens mit, aber
sie lösen keine Fund-Meldung aus.

Beides steckt auch im GPX-Export: Deine Leergänge kommen beim
Wiedereinlesen zurück.

## Deine Spots vollständig sichern und umziehen

*6. August 2026 · Version 1.57.0*

Der GPX-Export im Profil nimmt jetzt **alles** mit: nicht nur die
Fundorte, sondern jeden einzelnen Fund mit Art, Anzahl, Datum und Notiz,
dazu die Einstellung „Von Freigabe ausschließen". Liest du die Datei
wieder ein, steht dein Revier so da, wie du es verlassen hast — auch in
einem **anderen Konto**. Genau dafür ist es gedacht.

Beim Import erkennt die App eine solche Datei von selbst und zeigt eine
Liste zum Abhaken: alle auf einmal oder einzeln. Spots, die du schon
hast, sind vermerkt und nicht angehakt — dieselbe Datei zweimal
einzuspielen legt also nichts doppelt an. Anhaken kannst du sie trotzdem.

Die Datei bleibt gleichzeitig eine ganz normale GPX-Datei: Jede
Karten- oder Navi-App zeigt weiterhin deine Wegpunkte mit Namen und
Fundhistorie. Nebenbei behoben — die Fundliste stand dort bisher als
Fließtext in einer Zeile, jetzt steht sie untereinander.

**Ein Hinweis, den du vor dem Teilen bekommst:** Weil in der Datei auch
deine **Notizen** stehen, fragt die App jetzt nach, bevor sie das
Teilen-Fenster öffnet. Als Sicherung für dich selbst ist das gewollt —
weitergeben solltest du sie nur, wenn die Notizen jemand lesen darf.

## Wann welche Art gemeldet wird

*5. August 2026 · Version 1.56.0*

Im Spot-Blatt steht jetzt über dem Wetter ein neuer Abschnitt: **„Wann
diese Art gemeldet wird"** — zwölf Balken, einer je Monat, der laufende
hervorgehoben, dazu ein Satz wie „Steinpilz wird am häufigsten im August
bis September gemeldet."

Die Zahlen stammen aus echten Fundmeldungen aus Deutschland, Österreich
und der Schweiz — rund 300 000 Beobachtungen für die 89 Arten, für die es
genug davon gibt. Sie sind gegen den allgemeinen Meldeeifer verrechnet:
Im September und Oktober wird schlicht am meisten gesammelt und gemeldet,
und ohne diese Korrektur sähe jede Art gleich aus. Danach liegt zum
Beispiel die Zeit des Pfifferlings im **Juli**, nicht im August.

**Was der Abschnitt nicht ist:** eine Vorhersage. Er beschreibt frühere
Jahre, nicht dieses Wochenende — es steht kein Prozentzeichen darin und
keine Bewertung. Ob es sich gerade lohnt, hängt am Wetter, und das ist
eine andere Frage, an der noch gearbeitet wird.

Drei Dinge, die dazugehören: Die Kurven liegen **in der App**, sind also
ohne Empfang da und verraten niemandem, wonach du suchst. Arten mit zu
wenigen Meldungen bekommen bewusst gar keinen Abschnitt statt einer
Zackenlinie. Und wo ein Name für mehrere Arten steht — „Rotkappe",
„Hallimasch" —, sagt die App das dazu.

## Die Karte sagt dir, wenn ein Buddy einen Fund eingetragen hat

*5. August 2026 · Version 1.55.0*

Trägt ein Pilz-Buddy einen Fund ein — auf einem deiner Spots oder auf
einem, den er mit dir geteilt hat —, zeigt die Karte oben ein blaues
Banner: **„Neuer Fund von …"**. Antippen öffnet direkt den Spot mit dem
neuesten Fund; das X blendet den Hinweis aus. Beides merkt sich die App
auf dem Gerät, der Hinweis kommt also nicht nach jedem Neustart wieder.

Es gibt dafür keine Push-Nachrichten und keine E-Mails — der Hinweis
erscheint nur in der App, und es verlässt dafür kein einziges neues
Datum dein Gerät.

## Pilz-Buddies können Funde zu geteilten Spots eintragen

*5. August 2026 · Version 1.54.0*

Wenn ein Freund einen Spot mit dir teilt, kannst du dort jetzt **eigene
Funde eintragen** — dein Fund gehört dir, der Spot weiterhin deinem
Freund. In der Fundliste steht bei fremden Funden, von wem sie stammen.

Endet die Freundschaft oder das Teilen, sieht jeder wieder nur die
eigenen Funde — nichts wird gelöscht, und wer sich wieder anfreundet,
sieht auch die Funde des anderen wieder. Funde dritter Freunde bekommt
niemand zu sehen: Was du einträgst, sehen nur du und die Besitzerin
oder der Besitzer des Spots.

Statistik und GPX-Export zählen wie bisher nur deine eigenen Funde.

## Regenkarte ohne Farbblitz, Wetter am Spot aufgeräumt

*5. August 2026 · Version 1.53.0*

Beim Einschalten von **„Letzte 24 Stunden"** oder **„Letzte 30 Tage"**
blitzte bisher kurz die Karte des Wetterdienstes in fremden Farben auf,
bevor unsere eigene Darstellung sie ersetzte — samt falscher Legende im
Regen-Blatt. Das ist bereinigt: Während die Daten laden, bleibt die
Karte ruhig, und die richtige Legende steht sofort da. Nebenbei spart
das bei jedem Einschalten einen unnötigen Download von bis zu einem
halben Megabyte. Kommen gar keine Daten an (kein Empfang), zeigt die
App wie bisher das Bild des Wetterdienstes samt seiner Legende.

Dazu ein aufgeräumtes Erscheinungsbild im PilzBuddy-Stil, wie man ihn
aus den Anmelde-Mails kennt: Die Regensummen im Spot-Blatt stehen jetzt
**in einer cremefarbenen Kachel** mit den Werten fett in Grün, und die
Überschriften von Regen-Blatt, Legende und Wetter-Abschnitt tragen das
PilzBuddy-Grün.

## Deine E-Mail-Adresse lässt sich jetzt ändern

*5. August 2026 · Version 1.52.0*

Die dritte neue Konto-Option im Profil: **„E-Mail-Adresse ändern"**.
Wichtig ist das, weil an der Adresse mehr hängt, als man denkt — Freunde
finden dich darüber, und der Code bei „Passwort vergessen" geht an genau
dieses Postfach. Wer sein altes Postfach verliert, wäre sonst irgendwann
ausgesperrt.

Der Wechsel ist bewusst gründlich abgesichert: Er verlangt dein
aktuelles Passwort, und danach kommen **zwei Mails mit zwei
verschiedenen Codes** — eine an die bisherige, eine an die neue Adresse.
Erst beide Codes zusammen vollziehen den Wechsel. So kann niemand, der
nur kurz an dein entsperrtes Handy oder an eines deiner Postfächer
kommt, dein Konto auf eine fremde Adresse umziehen.

## Andere Geräte abmelden

*5. August 2026 · Version 1.51.0*

Im Profil gibt es jetzt **„Andere Geräte abmelden"**. Der Handgriff für
den Fall, dass ein Handy verloren geht oder ein geteiltes Tablet noch
angemeldet ist: Nach einer Rückfrage wird die Anmeldung überall beendet
— nur auf dem Gerät, auf dem du gerade bist, bleibst du drin.

Gut zu wissen: Ein Passwortwechsel allein beendet laufende Anmeldungen
nicht sofort. Erst dieser Knopf wirft sie wirklich raus.

## Dein Benutzername lässt sich jetzt ändern

*5. August 2026 · Version 1.50.0*

Im Profil gibt es neben „Passwort ändern" jetzt **„Benutzername
ändern"**. Der Name ist das, worunter Freunde dich in der Suche finden —
deshalb steht im Dialog auch dabei: Nach der Änderung finden sie dich
unter dem neuen Namen.

Nebenbei ist eine Lücke geschlossen: Benutzernamen sind jetzt auch dann
einmalig, wenn sie sich nur in Groß- und Kleinschreibung unterscheiden.
Ein zweiter „marcus" neben einem „Marcus" wäre für alle, die suchen,
dasselbe Konto gewesen.

## Wie warm war es an deinem Spot

*4. August 2026 · Version 1.49.0*

Zum Regen im Spot-Blatt kommt jetzt die **Temperatur**: Über den blauen
Balken liegen dünne Linien — die **Bodentemperatur in 5 cm Tiefe** (dort
lebt das Pilzgeflecht) und die Tageshöchst- und Tiefstwerte der Luft.
Beide Achsen sind beschriftet: links Grad, rechts Millimeter. Und an den
Enden der Zeitskala steht jetzt das Datum, rechts zum Beispiel
„gestern, 3.8." — damit klar ist, in welche Richtung sie läuft.

Die Werte kommen von der **nächstgelegenen Wetterstation** des Deutschen
Wetterdienstes, und genau die steht auch dabei: Name, Entfernung und
Höhe. Die Höhe gehört dazu, weil sie den größten Unterschied macht —
eine Station 300 Meter tiefer ist gut zwei Grad wärmer, und das rechnet
die App bewusst nicht heraus, sondern schreibt es dir hin.

Wie beim Regen gilt: Die Suche nach der nächsten Station läuft
**auf deinem Gerät**. Kein Wetterdienst erfährt, wo deine Spots liegen.
Die Frage im Spot-Blatt heißt jetzt „Wetterdaten laden" und deckt beides
ab — wer dem Regen schon zugestimmt hat, bekommt die Temperatur ohne
neue Frage dazu.

## Der Regen ist jetzt zu lesen

*4. August 2026 · Version 1.48.0*

Die Regensummen auf der Karte sahen bisher so aus: dünne Linien, und
dazwischen ein Farbton, den man kaum sah. Wer nicht wusste, was gemeint
ist, konnte es auch nicht herausfinden — eine Legende gab es nicht.

Jetzt sind es **Flächen**. Jedes Band hat seine Farbe, von sandgelb
(wenig) über grün bis blau (viel), und man erkennt auf einen Blick, wo
mehr und wo weniger gefallen ist. Die Linien dazwischen sind weg; sie
werden nicht mehr gebraucht.

Damit klar ist, was die Farben bedeuten, gibt es jetzt **eine Legende
unten links**. Sie erscheint, sobald du eine Regenebene einschaltest, und
verschwindet wieder, wenn du sie ausschaltest.

Wie stark die Farbe sein darf, ist auf dem Gerät ausprobiert worden: zu
blass, und man sieht die Bänder nicht; zu kräftig, und die Ortsnamen
verschwinden darunter. Der jetzige Wert liegt bewusst dazwischen.

Das **Regenradar** („jetzt" und „in einer Stunde") ist unverändert und
behält die Farben und die Legende des Wetterdienstes.

## Wie viel Regen an genau diesem Spot — Tag für Tag

*4. August 2026 · Version 1.47.0*

Im Blatt eines Spots steht jetzt ganz unten, wie viel Regen dort gefallen
ist: als Summe über 7, 14 und 30 Tage — und als **Balken für jeden
einzelnen der letzten 14 Tage**.

Der Verlauf ist der eigentliche Punkt. Eine Summe kann nicht
unterscheiden, ob die 40 Millimeter vor elf Tagen fielen oder gestern, und
für Pilze ist genau das der Unterschied. Darum steht unter den Balken auch
ein Satz wie „Letzter nennenswerter Regen vor 3 Tagen".

**Deine Fundstelle bleibt geheim.** Das ist keine Nebensache, sondern der
Grund, warum das Ganze so umständlich gebaut ist: Die App fragt *niemanden*
nach dem Wetter an deinem Spot. Sie lädt die Messwerte für ganz Deutschland
herunter und schlägt die Stelle **auf deinem Gerät** nach. Es gibt keine
Anfrage, in der deine Koordinate steht — auch nicht beim Wetterdienst.

Der Preis dafür sind Daten: Beim ersten Mal rund 0,9 MB, danach täglich ein
kleines Stück. Deshalb wird vorher gefragt, und erst nach deinem Tippen
geladen — im Wald gibt man das nicht ungefragt aus. Wer einmal zugestimmt
hat, wird nicht wieder gefragt.

Zwei Dinge, die dazugehören: Die Messung deckt **nur Deutschland** ab, und
sie endet **gestern** — der Wetterdienst rechnet ganze Tage ab. Was heute
vom Himmel kommt, zeigt weiterhin das Regenradar auf der Karte. Liegt ein
Spot außerhalb der Messung, bleibt der Abschnitt einfach weg statt eine
leere Zeile zu zeigen.

## Der Regen liegt jetzt in unseren Farben

*4. August 2026 · Version 1.46.0*

Die beiden Regensummen — **letzte 24 Stunden** und **letzte 30 Tage** —
sehen anders aus als gestern. Statt einer deckenden Fläche liegen dort
jetzt **Höhenlinien**, so wie auf einer Wanderkarte die Höhe: Jede Linie
verbindet Orte mit gleich viel Regen, von sandgelb (wenig) über grün bis
blau (viel). Zwischen den Linien liegt derselbe Ton noch einmal ganz
zart, damit man auf einen Blick sieht, wo mehr und wo weniger war.

Der Grund ist praktisch. Die alte Fläche legte sich über alles, und beim
Hineinzoomen waren Wege und Ortsnamen kaum noch zu lesen. Eine Ebene, die
einen daran hindert, zum Spot zu finden, ist keine Hilfe. Jetzt bleibt
die Karte darunter vollständig sichtbar.

Je weiter man herauszoomt, desto weniger Linien zeigt die Karte — sonst
läge über Deutschland ein Netz, in dem nichts mehr zu erkennen wäre. Was
welche Farbe bedeutet, steht im Regen-Blatt unter der Ebenenwahl.

Nebenbei sind die Daten dabei rund zehnmal kleiner geworden, was im Wald
am Datenvolumen zählt.

Das **Regenradar** („jetzt" und „in einer Stunde") bleibt unverändert in
den Farben des Wetterdienstes: Blau-Grün-Gelb-Rot ist die Darstellung,
die man aus jeder Wetter-App kennt, und daran soll nicht herumgebastelt
werden.

Wenn die neuen Daten einmal nicht erreichbar sind, erscheint
stillschweigend wieder die bisherige Darstellung. Die Regenkarte ist eine
Zugabe und darf nichts kaputt machen.

## Regen auf der Karte

*4. August 2026 · Version 1.45.0*

Der neue Tropfen-Knopf an der Karte legt Regendaten des Deutschen
Wetterdienstes über die Landschaft. Drei Zeiträume stehen zur Wahl, und
sie beantworten verschiedene Fragen:

- **Jetzt** und **in einer Stunde** — das Regenradar. Nützlich für die
  Frage, ob man jetzt losgeht oder lieber nicht.
- **Letzte 24 Stunden** — wo es seit gestern geregnet hat.
- **Letzte 30 Tage** — die wichtigste der drei. Daran sieht man, ob der
  Boden über den Monat wirklich durchfeuchtet wurde, und nicht nur, ob
  es einmal kurz geschüttet hat.

Bewusst zeigt die Ebene nur **Messwerte** und sagt nirgends „hier stehen
jetzt Pilze". Was daraus folgt, weißt du für deine Wälder besser als
jede Formel.

Zwei Dinge, die man wissen sollte: Die Summen gibt es nur für
Deutschland, und das Radar reicht nicht bis in den Osten Österreichs
oder den Westen der Schweiz — dort bleibt die Fläche grau, und die
Legende sagt das auch. Und die Ebene ist beim Start immer aus: Sie lädt
ein Bild aus dem Netz, und das soll im Wald niemand ungefragt tun.

## Deine Spots sind jetzt auch ohne Empfang da

*4. August 2026 · Version 1.44.0*

Wer die App im Wald **neu startete**, wo kein Netz war, sah bisher eine
Karte ohne einen einzigen Spot — ohne Hinweis, woran es lag. Genau dort,
wo die heruntergeladenen Offline-Karten eigentlich helfen sollen.

- Deine eigenen Spots samt Funden liegen jetzt zusätzlich **auf dem Handy**.
  Ohne Empfang zeigt die Karte diesen Stand, statt leer zu bleiben.
- Ein Hinweis oben sagt dir dabei, **von wann** die Daten sind — so weißt
  du, ob der Spot von gestern schon dabei ist.
- Sobald du wieder Empfang hast, aktualisiert sich alles von selbst und der
  Hinweis verschwindet.
- Beim Abmelden wird der Zwischenspeicher gelöscht, und in Googles
  Handy-Backup landet er nie: Deine Fundstellen bleiben deine.

## Eine neue Karten-Engine — erst zum Ausprobieren, jetzt Standard

*3. August 2026 · Versionen 1.39.0 bis 1.43.1*

Im Profil gibt es einen Schalter **„Neue Karten-Engine"** — nur in der
Android-App. Er stellt die Karte auf einen anderen Renderer um, der die
Offline-Karten spürbar flüssiger zeichnet, gerade beim schnellen Zoomen
und Wischen.

- Seit 1.40.0 zeigt die neue Engine auch **deine Spots, die Positionen
  deiner Freunde und deinen eigenen Standort** — antippen funktioniert wie
  gewohnt.
- Seit 1.41.0 kann sie auch die **Online-Karte**: Mit Empfang kommen die
  gewohnten OpenStreetMap-Kacheln, ohne Empfang springt sie automatisch
  auf deine heruntergeladenen Regionen um — nach denselben Regeln wie die
  bisherige Karte. Maßstab und Kartenhinweis sind auch da. Damit kann die
  neue Engine alles, was die alte kann.
- Mit 1.43.1 ist der Download der App wieder **ein Drittel kleiner**
  (45 statt 67 MB): Im Paket steckten Programmteile für Handy-Prozessoren,
  auf denen PilzBuddy gar nicht läuft. Sie sind jetzt draußen — an der App
  selbst ändert sich nichts.
- Seit 1.43.0 ist die neue Engine **Standard**: Im nachgemessenen
  Direktvergleich zeichnet sie beim Wischen rund fünfmal so viele Bilder
  pro Sekunde und braucht unter Dauerlast nur gut ein Drittel des
  Speichers. Der Schalter bleibt im Profil — wer mag, holt sich damit
  die bisherige Karte zurück.

## Die Karte friert nicht mehr ein — und bleibt nicht mehr grau

*3. August 2026 · Versionen 1.38.2 und 1.38.3*

Zwei Karten-Fehler, deren Folgen manche schon kannten, sind gefunden und
behoben:

- Ein seltener Grenzfall bei den Fingergesten konnte die Kartenansicht in
  einen kaputten Zustand bringen: Die App fror mitten in der Bewegung ein,
  bis Android sie zum Schließen vorschlug. Der kaputte Zustand wird jetzt
  an der Wurzel verworfen und kann gar nicht mehr entstehen.
- Nach einem kurzen Empfangsverlust (U-Bahn, Funkloch am Waldrand) blieben
  neue Online-Kacheln dauerhaft grau: Nur schon besuchte Gegenden
  erschienen noch, und erst ein App-Neustart half. Jetzt übersteht die
  Online-Karte den Wechsel und lädt danach normal weiter.

## Mehrere Pilzarten gleichzeitig filtern

*2. August 2026 · Versionen 1.38.0 und 1.38.1*

Im Filter-Blatt lässt sich jetzt mehr als eine Art anhaken. Wer im Herbst
sowohl nach Maronen als auch nach Pfifferlingen unterwegs ist, sieht beide
Sorten Fundstellen auf einer Karte statt nacheinander.

- Angehakt wird durch Antippen, noch einmal antippen nimmt die Art wieder
  raus.
- **„Alle Arten"** ganz oben räumt die Auswahl in einem Tipp weg — egal wie
  viele Häkchen gesetzt sind. „Nur meine Spots" bleibt davon unberührt, das
  sind zwei getrennte Schalter.
- Gezeigt wird, was zu **einer** der gewählten Arten passt. Nicht: wo alle
  gewählten zusammen vorkommen — das wäre fast immer die leere Karte.
- Oben auf der Karte stehen bei einer oder zwei Arten die Namen, ab drei die
  Zahl. Sonst wüchse die Zeile über die Karte.

## Zweitnamen: „Totentrompete" findet jetzt auch „Herbsttrompete"

*2. August 2026 · Version 1.37.0*

Viele Pilze haben zwei geläufige Namen, und für die App waren das bisher
zwei verschiedene Arten. Wer seine Fundstellen als „Totentrompete"
eingetragen hatte und später nach „Herbsttrompete" filterte, sah sie nicht.

- Beim Eintragen kannst du **beide Namen** tippen. Gespeichert wird immer
  derselbe — die Hauptbezeichnung. Darunter steht dann, wie der Pilz sonst
  noch heißt, damit du siehst, dass du richtig lagst.
- Der Filter auf der Karte, die Zahl der Fundstellen und die Top-Arten im
  Profil ziehen beide Namen zusammen. Das gilt auch für deine **alten**
  Funde: Du musst nichts nachtragen.
- In der Fundliste einer Stelle steht weiterhin, was du damals geschrieben
  hast. Der Eintrag ist dein Protokoll, den benennen wir nicht nachträglich
  um.
- Erkannt werden unter anderem: Totentrompete, Marone, Herrenpilz,
  Fichtensteinpilz, Riesenschirmling, Fette Henne, Austernpilz,
  Mairitterling, Butterröhrling, Rötender Wulstling, Flaschenbovist,
  Riesenstäubling, Nebelgrauer Trichterling, Winterrübling, Rotfüßchen und
  Spargelpilz.

**Eine Art wechselt die Zuordnung:** „Braunkappe" ist in der App bisher als
Marone geführt worden. Gemeint ist damit der Riesenträuschling — so heißt er
auch. Deine Spots mit diesem Namen bekommen deshalb ein anderes Symbol und
zählen ab jetzt zum Riesenträuschling.

**Der Igelstachelbart sieht endlich aus wie einer.** Er stand bei den
Baumpilzen und wurde als orange Konsole gezeichnet. Er wächst zwar an Holz,
ist aber ein weißlicher Knollen mit langen hängenden Stacheln — genau so
steht er jetzt auf der Karte. „Affenkopfpilz" und „Löwenmähne" werden als
Namen dafür erkannt.

Auch behoben: Im Profil zählten „Steinpilz" und „steinpilz" als zwei
verschiedene Arten und standen getrennt untereinander.

## Vier neue Pilzarten — und Hexenröhrlinge, die man unterscheidet

*2. August 2026 · Version 1.36.0*

Vier Arten, die ihr euch über das Rückmeldeformular gewünscht habt, stehen
jetzt in der Vorschlagsliste: **Netzstieliger Hexenröhrling**,
**Käppchenmorchel**, **Morchelbecherling** und **Böhmische Verpel**.

Jede hat ein eigenes Kartensymbol bekommen, statt nur das ihrer Gruppe:

- Die beiden **Hexenröhrlinge** sehen jetzt aus, wie sie im Wald aussehen —
  olivbrauner Hut über roten Poren auf gelbem Stiel. Auseinanderhalten kann
  man sie am Stiel: rotes Netz beim Netzstieligen, rote Flocken beim
  Flockenstieligen. Vorher waren beide ein brauner Pilz wie jeder andere,
  und der sah aus wie ein Steinpilz.
- Der **Morchelbecherling** steht als offene Schale mit Adern auf der Karte,
  nicht mehr als Morchelkegel.
- **Käppchenmorchel** und **Böhmische Verpel** haben beide ihren kleinen Hut
  auf dem langen blassen Stiel — die eine mit Waben, die andere mit
  Längsrillen.

Die Verpel lag außerdem in der falschen Schublade und wurde als grauer
Lamellenpilz gezeichnet. Sie steht jetzt bei den Morcheln und Lorcheln, wo
sie hingehört.

Dabei ist noch einer aufgefallen: Der **Semmelstoppelpilz** war ebenfalls
ein grauer Lamellenpilz — obwohl er gar keine Lamellen hat und semmelfarben
ist. Er hat jetzt seinen flachen, hell gebackenen Hut, und darunter sitzen
die Stoppeln, die ihm den Namen geben.

**Pilze ohne Lamellen haben jetzt eine eigene Schublade.** Sie hieß bisher
für alle „Lamellenpilz", und das steht sichtbar am Vorschlag, wenn du eine
Art eintippst. Für vier stimmte es nicht: Krause Glucke, Semmelstoppelpilz,
Habichtspilz und Ziegenbart heißen jetzt „Stachel-/Korallenpilz" und sehen
auch so aus. Die **Krause Glucke** und der **Ziegenbart** werden dabei ohne
Stiel gezeichnet — die haben nämlich keinen.

**Und die Artenliste ist gewachsen.** Dreizehn geläufige Pilze fehlten
schlicht: Maipilz, Nelkenschwindling, Rehbrauner Dachpilz,
Riesenträuschling, Rotfußröhrling, Körnchenröhrling, Grüngefelderter
Täubling, Speitäubling, Birnenstäubling, Lungenseitling, Habichtspilz,
Ziegenbart und Scheidenstreifling. Der Scheidenstreifling hat ein eigenes
Bild bekommen, weil er als Wulstling sonst rot mit weißen Punkten wäre —
und das ist er gerade nicht.

## Karte nach Pilzart filtern

*2. August 2026 · Version 1.35.0*

- Der neue Knopf mit dem Trichter öffnet ein Blatt mit allen Arten, zu denen
  du Funde hast — samt Zahl der Fundstellen. Eine antippen, und die Karte
  zeigt nur noch diese.
- Gefiltert wird über **alle** Funde einer Stelle, nicht nur den letzten:
  Wenn du dort einmal Pfifferlinge gefunden hast, findest du sie unter
  „Pfifferling" wieder — auch wenn zuletzt etwas anderes dort stand.
- Getrennt davon schaltbar: „Nur meine Spots" blendet die deiner Freunde aus.
- Solange gefiltert ist, steht das oben auf der Karte, mit einem Kreuz zum
  Aufheben. Beim nächsten Start liegt wieder alles auf der Karte — ein
  vergessener Filter, der Fundstellen versteckt, wäre der teurere Fehler.

## Updates wieder in der App

*2. August 2026 · Version 1.34.0 · nur Android, nur die Version von GitHub*

Bisher öffnete „Update" den Browser; die geladene Datei musste man dann
selbst finden und antippen. Das geht wieder direkt in der App.

- Im Update-Hinweis auf „Jetzt aktualisieren" tippen: Die App lädt die neue
  Version mit Fortschrittsanzeige und übergibt sie an Android, das wie
  gewohnt nach der Bestätigung fragt.
- Beim ersten Mal fragt Android einmalig, ob PilzBuddy Apps installieren
  darf. Der Dialog führt mit einem Tipp zu dieser Einstellung — danach ist
  jedes weitere Update ein Tipp.
- Der Weg über den Browser bleibt daneben stehen. Wenn beim Laden etwas
  schiefgeht, sagt der Dialog, was los war, und bietet ihn an.
- Deine Spots und heruntergeladenen Karten bleiben bei einem Update
  selbstverständlich erhalten.

## Zwei Kleinigkeiten aus dem Wald

*2. August 2026 · Version 1.33.1*

- Beim Anlegen eines **neuen** Spots ist das Artenfeld jetzt leer, statt die
  zuletzt gemeldete Art vorzuschlagen. Die musste man vorher jedes Mal
  löschen, wenn der nächste Fund eine andere Art war. Deine eigenen Arten
  stehen weiter als Knöpfe darüber — ein Tipp statt Tippen. Beim
  **Wiederbesuch** bleibt die Art des Spots wie bisher vorbelegt.
- Der Umschalter zwischen Online- und Offline-Karte merkt sich deine Wahl
  über den Neustart hinweg. Vorher stand die App nach jedem Start wieder auf
  Online — ausgerechnet dort, wo man sie bewusst umgestellt hatte.

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
