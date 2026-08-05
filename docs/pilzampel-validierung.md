# Rückwärtsvalidierung der Pilzampel — Methode

Stand: 6. August 2026 · Werkzeug: `tool/ampel_validate.py` · Konzept:
`docs/pilzampel-konzept.md` (Schritt 3)

Das Konzeptpapier stellt eine Bedingung vor die Ampel: **erst prüfen, ob sie
etwas taugt.** Diese Seite beschreibt, wie geprüft wird und woran die Prüfung
scheitern kann. **Die Ergebnisse erzeugt der Lauf** und schreibt sie über
diese Datei — was hier steht, ist die Methode.

> `python3 tool/ampel_validate.py --out docs/pilzampel-validierung.md`

## Die Frage

Wörtlich aus dem Konzept: „Steht die Ampel an Fundtagen höher als an
zufälligen Tagen derselben Saison? Wenn nicht, taugt das Modell nichts — und
das merkt man **vor** dem Ausliefern."

Genau daran ist das BMVI-Projekt Pilz4You gescheitert: Modell gebaut, App nie
veröffentlicht, weil die Fundbeobachtungen als Zielgröße fehlten. Keiner der
~45 recherchierten Dienste publiziert eine Validierung.

## Der Aufbau

Zu jeder Fundmeldung wird ein **Vergleichstag** gezogen: gleicher Ort,
gleiches Jahr, 14–45 Tage daneben. Für beide Tage rechnet dasselbe Modell
einen Wert, und gezählt wird, wie oft der Fundtag vorn liegt (**AUC**;
0,50 = zufällig).

Drei Dinge, die dieser Zuschnitt leistet:

- **Der Standort kürzt sich heraus.** Beide Tage liegen am selben Fleck —
  gleicher Wald, gleiche Baumart, gleicher Boden. Bei Holzbewohnern erklärt
  dieser Faktor sonst 56–59 % der Varianz (Alday/Karavani et al. 2017). Die
  Frage lautet nur noch: Warum an *diesem* Tag und nicht drei Wochen später?
- **Die Jahreszeit kürzt sich heraus** — und damit der Zirkelschluss. Die
  Saisonkurven (`docs/pilzampel-saisonkurven.md`) stammen selbst aus GBIF;
  liefen sie hier mit, bestätigte sich das Modell selbst. Der Saisonfaktor
  geht deshalb **nicht** ein.
- **Der Mindestabstand von 14 Tagen** verhindert, dass sich die
  26-Tage-Regenfenster zu stark überlappen. Zwei Tage, die fünf Tage
  auseinanderliegen, teilen 21 von 26 Regentagen — man vergliche ein Wetter
  mit sich selbst.

### Das Modell

Nach dem Konzeptpapier, kalibriert an den Bielefelder Zahlen (zehn Jahre
nahezu tägliche Steinpilz-Erfassung): Niederschlag über **26 Tage**
kumuliert (ältere Tage schwächer gewichtet), Temperatur als Glocke um
**13 °C** über 20 Tage. Die Breite der Glocke (5 K) ist *gesetzt*, nicht
gemessen — das Papier nennt einen Gipfel, keine Streuung.

### Zwei Kontrollen, die Verschiedenes prüfen

**Placebo — prüft die Methode.** Zwei fundlose Tage treten gegeneinander an,
beide nach derselben Vorschrift gezogen. Hier *muss* 0,50 stehen. Alles
andere hieße, dass schon die Ziehung verzerrt, und dann wäre jede andere
Zahl wertlos.

Der Anker ist dabei entscheidend: Der zweite Tag wird vom **ersten
Vergleichstag** aus gezogen, nicht vom Fundtag. Zieht man beide vom selben
Punkt, hebt sich eine einseitige Vorschrift symmetrisch auf und bleibt
unentdeckt — während Fund- und Vergleichstag sehr wohl auseinanderlägen.
(Genau so zuerst gebaut, beim Gegenprüfen aufgefallen.)

**Arten-Kontrolle — prüft, ob das Modell artspezifisch wirkt.** Hallimasch,
Stockschwämmchen, Austernseitling. **Nicht**, weil diese Arten kein Wetter
spürten — der Austernseitling ist ein Kältefrüchter mit Gipfel im Dezember
und reagiert sehr wohl, nur auf anderes. Geprüft wird enger: Dieses Modell,
gebaut aus Steinpilz-Literatur, darf bei ihnen nicht passen. Ein Wert
**unter** 0,50 ist deshalb kein Fehlschlag, sondern ein Beleg.

## Woher die Funde kommen — und woher nicht

| Quelle | Menge (DE) | Ort | Datum | Verwendung |
|---|---|---|---|---|
| **GBIF** | 2487 allein Steinpilz ab 2006 | Median **250 m**, 238/281 unter 1 km | 300/300 taggenau | **Wetter-Validierung** |
| Mushroom Observer | 2466 gesamt, aber **1–6 je Speisepilz-Art** | 0/100 mit Koordinate | taggenau | geprüft, **trägt nicht** |
| pilzforum.eu | Freitext im Beitrag | Region | Posting- ≠ Funddatum | nicht verwendet |
| 123pilzforum.de | — | — | — | **ClaudeBot in robots.txt gesperrt** |

**Warum grobe Ortsangaben ausscheiden, gemessen:** Im DWD-Raster
(RADOLAN-W4, 2347 Rasterpunkte in „Südwestdeutschland" — genau die
Ortsangabe, die Mushroom Observer liefert) reicht die 30-Tage-Regensumme von
14 mm (10 %) bis 82 mm (90 %), Faktor **5,9**, Spannweite bis 255 mm. Die
Sammlerschwelle liegt bei ~100 mm. Der Unterschied zwischen Dürre und guten
Bedingungen liegt vollständig *innerhalb* der Ortsangabe; als unabhängige
Variable wäre sie Rauschen.

**Und warum die Saison-Gegenprüfung an einer zweiten Population
ausfällt:** Für den Monat genügte die grobe Ortsangabe — aber Mushroom
Observer hat für unsere Speisepilze nur 1 bis 6 Meldungen je Art. Die 2466
deutschen Beobachtungen verteilen sich auf hunderte Arten. Der Schalter
`--crosscheck` bleibt im Werkzeug und meldet zu dünne Arten, die Idee
braucht aber eine andere Quelle.

## Zwei Fallen, beide beim Bauen eingetreten

**1. Ein Rate-Limit, das stillschweigend Jahre verschluckt.** Open-Meteo
gewichtet seine Aufrufe nach Orten × Variablen × Tagen. Alle Funde über die
volle Saison wären ~22.600 Aufrufe bei einem Tageslimit von 10.000 — der
erste Versuch lief mitten in der zweiten Art in ein hartes „try again
tomorrow". Er schrieb trotzdem einen Bericht, auf **3 von 20 Jahren**, mit
völlig plausiblen Zahlen (Steinpilz 0,627, p < 0,001). Niemand hätte ihnen
angesehen, dass 85 % der Datenbasis fehlt.

Daraus zwei Änderungen: Ein ausgefallenes Jahr **bricht den Lauf ab** statt
übersprungen zu werden — Pilzjahre unterscheiden sich um den Faktor 10, ein
fehlendes verschiebt jede Zahl. Und der Bedarf wurde zugeschnitten: 500
Funde je Art (Zufallsstichprobe, fester Seed) über nur den gebrauchten
Zeitraum, zusammen ~3.700 Aufrufe. Mehr braucht es nicht — der
Standardfehler einer AUC liegt bei 500 Paaren um 0,02.

**2. Ein Selbsttest, der sich selbst bestätigt.** Die Prüfung des
Mindestabstands verglich gegen dieselbe Konstante, die sie absichern sollte,
und ging deshalb auch bei einem Tag Abstand durch. Jetzt bindet sie die
Anforderung (`CONTROL_MIN_GAP >= RAIN_WINDOW // 2`).

## Was diese Validierung nicht kann

- **Keine Negativbeispiele.** Weder GBIF noch die App kennen „war da, nichts
  gefunden". Der Test misst deshalb, ob Fundtage wetterseitig *auffällig*
  sind — nicht, wie oft die Ampel richtig liegt. Für eine Kalibrierung
  bräuchte es Leergänge (offene Entscheidung 2 im Konzeptpapier).
- **Kein Waldtyp.** Der ist hier zwar herausgekürzt, aber er ist der zweite
  Teil von #158 und für die Ampel selbst offen: Sie wird nie sagen können
  „hier stehen Pilze", solange sie Nadel-, Laub- und Mischwald nicht
  unterscheidet.
- **Melde- statt Fruchtungstage.** GBIF kennt den Tag der Beobachtung. Ein
  Pilz, der drei Tage vorher aufging, zählt als Fund des Tages, an dem
  jemand vorbeikam.
