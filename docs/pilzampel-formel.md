# Die Formel der Ampel — woher jede Zahl kommt

Stand: 2026-09-19 · Verlangt von `docs/pilzampel-fahrplan.md` („Herkunfts­tabelle:
gesetzt → gemessen") und `docs/pilzampel-auftrag-2.md`, Abschnitt 5

Diese Seite beantwortet genau eine Frage: **Welche Konstante der Ampel ist
gemessen, welche ist gesetzt — und wenn gemessen, in welchem Design?**

Sie ändert keine Konstante. Wo hier etwas herabgestuft wird, betrifft das
die Herkunftsangabe, nicht den Wert.

---

## Die Formel

    Score = Regenfaktor(26 d) · exp( −((T̄₂₀ − Optimum) / σ)² )

Die Saisonkurve ist **kein Faktor**, sondern ein Tor an den Spots
(`lib/features/ampel/ampel_scan.dart`). Sie steht deshalb nicht in dieser
Tabelle.

## Die Herkunftstabelle

Drei Stufen, und die mittlere ist neu:

| Stufe | heißt |
|---|---|
| **gesetzt** | nie gemessen — eine Annahme, die plausibel aussieht |
| **gemessen (Design A)** | gemessen, aber in einem Design, das die Jahreszeit mitmisst |
| **gemessen (Design B)** | gemessen gegen dasselbe Datum anderer Jahre — der Kalender ist heraus |

| Konstante | Wert | Herkunft | Beleg |
|---|--:|---|---|
| `ampelRainWindow` | 26 d | **gesetzt** — aus der Sammlerregel „100 mm in 30 Tagen", heruntergerechnet | `docs/pilzampel-konzept.md` |
| `ampelRainSaturationMm` | 87 mm | **gesetzt** — dieselbe Regel | `docs/pilzampel-konzept.md` |
| `ampelTempWindow` | 20 d | **extern gemessen** — Bielefelder Steinpilz-Reihe, zehn Jahre, ein Standort, eine Art | Brejon Lamartiniere & Hoffman 2025 |
| `ampelOptimumC` (herbst) | 13,0 °C | **extern gemessen** — dieselbe Reihe. In GBIF nie angepasst, aber an fremden Arten geprüft | `docs/pilzampel-herbstklasse-messung.md` |
| `ampelTempSigma` | 5,0 K | **gesetzt** — das Papier nennt einen Gipfel, keine Streuung. Am 2026-09-18 angegriffen und **nicht geschlagen** | `docs/pilzampel-h1-ergebnis.md` |
| `ampelSommerClass.optimumC` | 17,5 °C | **gemessen (Design A)** — angepasst auf DE ≤ 2018, Hold-out AT+CH bestanden. **Siehe Herabstufung unten.** | `docs/pilzampel-artenfenster-messung.md`, `…-holdout.md` |
| `ampelHerbstClass` Schwellen | 0,187 / 0,512 | **gemessen (Design A)** — 50-%- und 80-%-Quantil der Score-Verteilung an Vergleichstagen, Anpassjahre | `docs/pilzampel-schwellen-messung.md` |
| `ampelSommerClass` Schwellen | 0,287 / 0,677 | **gemessen (Design A)** — dito | `docs/pilzampel-schwellen-messung.md` |
| Höhenkorrektur | 0,65 K/100 m | **extern gesetzt** — trockenadiabatischer Standardwert, nicht an unseren Daten geprüft | `lib/features/ampel/ampel_providers.dart` |
| Messbasis | `era5_seamless` | **gemessen** — der Instrumentwechsel und seine Folgen sind beziffert | `docs/pilzampel-messbasis.md` |

---

## Herabstufung vom 2026-09-19: die 17,5 °C des Pfifferlings

**Bisher stand diese Zahl als „gemessen" da. Das war zu stark.**

Sie wurde mit `tool/ampel_validate.py --fit` auf DE ≤ 2018 angepasst und
in AT+CH geprüft — beides in **Design A**, wo der Vergleichstag 26 bis 45
Tage neben dem Fund im selben Jahr liegt. Bei einem Sommerfrüchter heißt
das Frühjahr oder Herbst, und beides ist kühler als Juli. Der Fundtag
sieht dort zwangsläufig warm aus, und ein angepasstes Optimum wandert
nach oben, ohne dass etwas über das Wetter gesagt wäre.

Dass genau das passiert ist, legt das bedingte Logit in Design B nahe:
Dort steht der Pfifferling bei **13,16 ± 0,94 °C** (cluster-robust), rund
viereinhalb Standardfehler unter der ausgelieferten Konstante und näher
an der Herbstklasse als an seinem eigenen Fenster
(`docs/pilzampel-logit.md`). Er ist die einzige Art, deren Abstand zur
ausgelieferten Zahl den robusten Fehler übersteht.

**Was sich dadurch NICHT ändert:**

- **Der Wert bleibt bei 17,5 °C.** Eine Konstante nach dem Blick auf eine
  Nebenrechnung zu verschieben, wäre genau der Griff, gegen den der ganze
  Aufbau antritt.
- **Der Hold-out-Erfolg bleibt als Messung stehen.** Er wurde in Design A
  erzielt und gilt dort; die Zahlen in `…-holdout.md` werden nicht
  angefasst.
- **Der Pfifferling bleibt die bestbelegte Art.** In Design B steht er
  auf „belegt" und liegt +0,054 über seiner artgematchten Referenz
  (`docs/pilzampel-kontrolldesign.md`).

**Was sich ändert:** Wer künftig liest „das Fenster des Pfifferlings ist
gemessen", liest jetzt dazu, in welchem Design. Wer es anfassen will,
braucht eine eigene Registrierung — und die müsste in Design B laufen.

Dieselbe Herabstufung gilt sinngemäß für **jede** Zeile, die oben
„gemessen (Design A)" trägt, auch für die vier Schwellen. Phase 1.5 hat
gezeigt, dass Design A bei den Herbstarten rund 0,09 AUC Kalender enthält
(`docs/pilzampel-kontrolldesign.md`); eine auf Design A geeichte Schwelle
trägt denselben Anteil.

---

## Stand der Dinge, 2026-09-19

**Drei registrierte Versuche, die gesetzten Konstanten zu verbessern,
sind ergebnislos geblieben.**

| # | Versuch | Ausgang | Beleg |
|--:|---|---|---|
| 1 | **H3** — Zwei-Phasen-Wintermodell (Frostreiz, dann Wärmesumme) | **geschlossen, nicht registriert.** Die Prämisse ist gemessen und trägt nicht: Die Frost-Signatur des Samtfußrüblings (67 % gegen 44 % Frosttage) wird gegen dieselben Kalendertage anderer Jahre zu 70 % gegen 73 %. | `pilzampel-kontrolldesign.md` |
| 2 | **H1** — schmalere Glocke, 3,25 K statt 5,0 K | **nicht bestanden.** Keine Art erreicht die Latte; bei den sechs ausgelieferten liegt der Gewinn zwischen −0,011 und +0,010. | `pilzampel-h1-ergebnis.md` |
| 3 | **H5** — Feuchte allein, Temperatur raus | **nicht registriert.** Die Beobachtung dahinter stammte aus den Prüfjahren und kehrt auf den Anpassjahren nicht wieder: dort gilt sie bei 1 von 6 Arten statt bei 6 von 6. | `pilzampel-h5-vorpruefung-ergebnis.md` |

Dazu zwei Nachmessungen, die nichts verändert haben und viel erklären:
das bedingte Logit mit cluster-robusten Fehlern (`pilzampel-logit.md`)
und die Alterungsfrage auf den geteilten Anpassjahren
(`pilzampel-alterung.md`).

### Warum das kein schwaches Ergebnis ist

Die Ampel rechnet heute **Zahl für Zahl dasselbe wie vor vier Wochen**.
Was sich geändert hat, ist, was wir über sie sagen dürfen:

- **Sie überlebt den Kalender.** Die sechs ausgelieferten Arten halten
  auch dann, wenn man die Jahreszeit vollständig herausrechnet (Design
  B, 0,63 bis 0,70) — und liegen +0,054 bis +0,116 über einer Referenz
  aus denselben Gegenden und Monaten. Vorher war das eine Hoffnung.
- **Die drei Arten, die zusammenbrechen, waren nie ausgeliefert.**
  Hallimasch, Austernseitling und Samtfußrübling fallen in Design B auf
  0,49 bis 0,51. Hätte jemand sie zwischendurch freigegeben, wüsste man
  es heute erst recht nicht.
- **Jede Art trägt eine Evidenzstufe**, und seit 1.143.0 steht sie in
  der App: fünf „gut belegt", eine „unsichere Datenlage". Keine Art
  verliert ihre Ampel — die Stufe begrenzt die Behauptung.
- **Drei Konstanten sind als „gesetzt" kenntlich**, zwei weitere als
  „in einem Design gemessen, das die Jahreszeit mitmisst". Vorher stand
  alles gleichrangig da.
- **Die Prüfachsen sind gezählt** (`pilzampel-pruefachsen.md`), und
  seit dem 2026-09-19 geht keine Frage mehr an eine Achse, ohne vorher
  auf den Anpassjahren geprüft zu haben, ob sie dort überhaupt
  beantwortbar ist. Diese Regel hat auf ihrem ersten Lauf eine Achse
  gespart.

**Ein erfolgloser Angriff ist keine Bestätigung.** σ = 5 K hat H1
überstanden; das heißt, dass 3,25 K bei festgehaltenem Optimum nicht
besser trennt — nicht, dass 5 K richtig ist. Dasselbe gilt für alles
andere in der Tabelle oben. Die Ampel ruht weiterhin auf mehr Gesetztem
als auf Gemessenem, und genau deshalb steht sie hinter einem Schalter
und heißt „experimentell".

### Was die nächste Verbesserung bräuchte

Nicht noch eine Konstante, sondern **andere Daten**. Die Achsen sind
knapp (AT+CH fünfmal benutzt, einmal bestanden), und die offenen Fragen
hängen an Material, das heute nicht da ist:

- **Mehr Winter.** Beim Samtfußrübling ist der Standardfehler über
  Fundjahre fast doppelt so groß wie bei unabhängigen Paaren. Mehr
  Meldungen aus denselben zwanzig Wintern helfen kaum; mehr Winter
  schon.
- **Begehungen mit „nichts gefunden"** aus der App selbst (#199). In
  einer solchen Stichprobe heißt Abwesenheit wirklich Abwesenheit und
  nicht „niemand war da" — das ist die Grenze, an der jede Zahl dieser
  Arbeit endet.
