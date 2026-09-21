# Pilzampel — Plan: Mindesttemperatur und Frost in der Klasse „Austernseitling & Co.“ (#497)

Stand: 2026-09-21. Vorab festgelegt, bevor im Labor gerechnet wird — wie
`docs/pilzampel-holz-winter-plan.md` und die Regeln in
`pilzbuddy-lab/PLAN.md` (ein Score, jeder Vergleich gepaart, Merkmale
und Regel vor dem Lauf, nichts auf dem Testteil zum Auswählen).

Anlass (#495, Betreiber): „Der Pilz braucht initial Minustemperaturen,
daher sollte die Mindesttemperatur dafür ausgewertet werden.“

## 1. Ausgangslage — was schon gemessen ist

**Die Klasse.** „Austernseitling & Co.“ (Holz & Winter, acht Arten:
Austernseitling, Judasohr, Krause Glucke, Leberpilz, Lungenseitling,
Rehbrauner Dachpilz, Samtfußrübling, Schwefelporling) rechnet seit
1.152.0 ein freies bedingtes Logit mit fünf Konstanten
(`log_regen 0,188 · T 0,132 · T² −0,00446 · Feuchte 0,0022 ·
Feuchte×T −0,000442`). Angenommen in Lauf 18 auf den Testblöcken
DE + AT/CH: +0,357 [+0,238, +0,503] ▲ gegen die 13-°C-Glocke, sechs von
acht Arten ▲, keine ▼, und +0,020 [+0,000, +0,038] ▲ gegen die
Klimatologie. AUC 0,544 → 0,560.

**Was der Scheitel sagt.** Ohne Feuchte-Kopplung liegt das Maximum bei
0,132 / (2 · 0,00446) ≈ 14,8 °C; bei 60 % nFK zieht die Kopplung den
Term auf 0,106 und den Scheitel auf ≈ 11,8 °C. 15 °C Anfang September
liegt also mitten im Fenster — das ist, was #495 als „unrealistisch“
gesehen hat.

**Warum das kein Fehler des Fensters ist.** Die Klasse wird im
Case-Crossover geschätzt: Fundtag gegen Kontrolltage derselben Stelle,
höchstens ±7 Tage entfernt (`DAY_JITTER`). Die Saison kürzt sich in
diesem Vergleich fast ganz heraus. Die Klasse sagt „Bedingungen passen
innerhalb der Saison“, nie „es ist die Saison“ — die Saison stellt seit
1.157.0 (#498) das Tor je Klasse in der App. Und die Klasse ist
gemischt: Saisonanteil im September Krause Glucke 100, Leberpilz 100,
Rehbrauner Dachpilz 76, Lungenseitling 32 — gegen Austernseitling 3 und
Samtfußrübling 1.

**Frost ist im Labor nicht neu.** Lauf 06 (Ablation, sechs Herbstarten)
hatte `frosttage` (Tage mit Tmin ≤ 0 °C in den letzten 14 Tagen) als
Sprosse: bei fünf Arten nichts, bei der Herbsttrompete +0,126 ▲ gegen
die Formel, aber gegen die vorherige Sprosse (+ Bodentemperatur) −0,011
n.s. — kein eigenständiger Beitrag. 07/08 (Boosting auf 191 Rohspalten,
verteilte Lags) schlossen: Aus diesen Reihen ist für die Herbstarten
nichts mehr herauszuholen. **Für Holz & Winter wurde Frost nie
geprüft** — die acht Arten kamen erst mit 12/13 ins Labor, und 14/18
haben nur die fünf Formel-Merkmale je Cluster verglichen.

**Die Daten liegen bereit.** Jedes Stratum trägt eine 28-Tage-Reihe
`tmin` (Open-Meteo `temperature_2m_min` an der Fundkoordinate,
`SPAN_LOOKBACK = 28`) — für alle 60 Arten aus Lauf 12, lokal, ohne
Abruf. Strata der acht Arten (Erkundung DE, Lauf 12): Schwefelporling
1 539, Judasohr 1 377, Austernseitling 1 015, Rehbrauner Dachpilz 954,
Krause Glucke 767, Samtfußrübling 674, Leberpilz 458, Lungenseitling 239.

## 2. Die Frage, ehrlich zerlegt

Der Satz „braucht initial Minustemperaturen“ enthält zwei verschiedene
Behauptungen, und das Design kann nur eine davon direkt messen:

- **H1 — kurzfristig:** Frost in den letzten ein bis vier Wochen macht
  einen Tag zum Fundtag, verglichen mit Tagen ±7 derselben Stelle. Das
  ist ein Merkmal wie Regen oder Feuchte und im Case-Crossover sauber
  schätzbar.
- **H2 — saisonal:** Nach dem ERSTEN Frost der Saison beginnt die
  Fruchtung überhaupt. Innerhalb eines Stratums (±7 Tage) ist „erster
  Frost vorbei“ fast immer für alle Tage gleich; Information tragen nur
  die Strata, die den ersten Frost überspannen. Dafür braucht es eine
  längere Reihe (der erste Frost liegt oft 30–90 Tage vor dem Fund) —
  und der Teil, der sich mit dem Kalender deckt, ist genau das, was die
  Klimatologie-Baseline und in der App das Saison-Tor schon tragen.

Der Plan misst H1 vollständig aus dem Bestand (Stufe 1) und H2 nur, wenn
der Betreiber die längere Reihe freigibt (Stufe 2, eigener Abruf).

## 3. Merkmale — vorab festgelegt

Alle aus `tmin` je Stratum, `FROST_C = 0 °C` wie im öffentlichen
Werkzeug (`av.FROST_C`):

| Merkmal | Definition | Stufe | Live in der App? |
|---|---|---|---|
| `frosttage_w` | Tage mit Tmin ≤ 0 °C in den jüngsten w Tagen, w ∈ {7, 14, 21, 28} | 1 | ja — die Stationstabelle trägt `min` je Luftstation für 20 Tage (w ≤ 20) |
| `tmin_min_14` | kälteste Nacht der jüngsten 14 Tage (°C) | 1 | ja, dieselbe Spalte |
| `frost_ja_28` | 1, wenn in 28 Tagen mindestens eine Frostnacht | 1 | nur mit w ≤ 20 |
| `tage_seit_erstfrost` | Tage seit der ersten Frostnacht der Saison (ab 1. August), gedeckelt bei 120; 0 = noch keiner | 2 | **nicht heute** — bräuchte je Station ein Feld `first_frost_on`, das CI aus den DWD-Tagesdaten (`kl` recent) schreibt; klein, aber ein eigener PR |

Das Fenster w wird auf den Erkundungsblöcken per OOF-Log-Likelihood
gewählt (alle vier berichtet); die Wahl fällt im Skript, nicht im
Nachhinein. Regel aus `PLAN.md`: **Was die App nicht live hat, geht
nicht in Phase G.** Ein Stufe-2-Merkmal wäre also nur mit dem
Stations-Feld auslieferbar.

## 4. Kandidaten und Vergleiche

Alle auf denselben Strata (vollständig für alle Merkmale), Leave-One-
Year-Out, DACH-Erkundungsblöcke (`bauen_dach`, `laender=("DE","AT","CH")`),
jeder Abstand ein gepaarter Bootstrap über Fundjahre (2000 Züge),
Score wie immer Log-Likelihood je Stratum, AUC daneben.

| | Kandidat | gegen |
|---|---|---|
| K0 | das angenommene Logit (5 Konstanten), ganze Klasse | Referenz |
| K1 | K0 + `frosttage_w` (eine Konstante) | K0 |
| K2 | K0 + `tmin_min_14` | K0 |
| K3 | Teilung: **Winter** {Austernseitling, Samtfußrübling, Judasohr} und **Holz Sommer/Herbst** {die fünf anderen}, je ein eigenes Logit (5) | K0 auf denselben Strata |
| K4 | K3-Winter + `frosttage_w` | K3-Winter |
| K5 (Stufe 2) | K0 + `tage_seit_erstfrost` | K0 |

Dazu je Kandidat der Abstand zur **Klimatologie** (Kalender allein) —
weil ein Frostmerkmal, das nur die Saison nachzeichnet, gegen K0 gewinnen
könnte, ohne etwas zu sagen, was der Kalender nicht sagt.

**Entscheidungsregel, vorab:**

1. Angenommen wird die **einfachste** Fassung, die gepaart gegen ihre
   Referenz **gesichert gewinnt** (▲) — nicht „nicht verliert“: Ein
   zusätzliches Merkmal muss sich verdienen, eine Teilung der Klasse
   erst recht (zwei Parametersätze in der App).
2. **Alle oder keine:** Ein angenommener Kandidat darf keine Art
   gesichert verschlechtern (die Lehre aus Herbst-Holz und Kalt vom
   2026-09-13).
3. Gegen die Klimatologie darf der Kandidat nicht hinter K0
   zurückfallen.
4. **Der Testteil ist verbraucht** (DE `8abd07e87e24` in 15, AT/CH
   `96a8023b1610` in 18). Er wird einmal **gegengeprüft** (Score,
   keine Auswahl, alle Kandidaten zugleich) und berichtet. Ein ▼ dort
   stoppt die Auslieferung; ein ▲ dort ist KEINE Bestätigung, weil die
   Blöcke schon zum Auswählen benutzt wurden.
5. Die echte Bestätigung kommt mit neuen Daten: der nächste
   GBIF-Download nach dem Winter 2026/27 (Funde Nov 2026 – Mär 2027,
   die kein Lauf je gesehen hat). Bis dahin trägt ein ausgelieferter
   Frost-Term die Stufe „auf Erkundungsblöcken belegt, gegengeprüft“ —
   und die Klasse bleibt „experimentell“.

**Mit berichtet, ohne Entscheidungsgewicht:** die Günstig-Quote an
Vergleichstagen vorher/nachher (die beiden Stufenschwellen der Klasse
sind Quantile und würden neu gezogen, Produktentscheidung 80 %); die
Koeffizienten je Kandidat; ein Placebo (Frostmerkmal je Stratum
permutiert — muss auf 0 fallen, sonst ist der Lauf falsch verdrahtet).

## 5. Ablauf im Labor

1. **Lauf 19** `laeufe/19_frost_holz_winter.py`, Bericht
   `berichte/19-frost-holz-winter.md`, gespiegelt nach
   `Claude_exchange/Pilzampel-lab/`. Messbasis der Worktree-Pin
   `9a8a2c414f`; vorab prüfen, dass die Strata der acht Arten `tmin`
   tragen (Lauf 12 hat die Zusatzfelder mitgeholt; fehlt es, liefert
   `stratum_merkmale` `None`, und der Lauf sagt es, statt 0 zu zählen).
2. Merkmal `frosttage` gibt es in `lab/merkmale.py` (Fenster 7/14/21/28
   registriert); neu sind `tmin_min_14` und `frost_ja_28`, mit
   Selbsttest — und je einer Gegenprobe, die den Test absichtlich rot
   macht.
3. **Stufe 2 nur nach Freigabe:** `SPAN_LOOKBACK` von 28 auf 120 im
   Werkzeug des Pins, erneuter Abruf der acht Arten aus der lokalen
   Open-Meteo-Instanz (Docker, je Art Sekunden bis Minuten), eigener
   Cache-Ordner, damit die 28-Tage-Strata aller anderen Läufe
   unverändert bleiben.
4. Ergebnis in `PLAN.md` des Labors und als Nachtrag hier; die
   Entscheidung über die App-Seite trifft der Betreiber auf dem
   Bericht.

Aufwand: Stufe 1 ein Vormittag (Rechnen Minuten, Schreiben länger);
Stufe 2 zusätzlich Abruf und ein Werkzeugparameter.

## 6. Was das nicht ist

- Kein App-Code, bevor der Bericht steht. Weder `ampel_model.dart` noch
  `tool/ampel_validate.py` werden angefasst.
- Keine Änderung an den Glocken-Klassen (13 °C, 14,5 °C); die Frage
  gilt allein Holz & Winter.
- Kein Saison-Tor im Labor — das Tor ist Produkt, keine Modellgröße,
  und die Klimatologie-Baseline misst ohnehin, was der Kalender kann.
- Keine Neuanpassung der fünf angenommenen Konstanten in K1/K2: Das
  Frostmerkmal kommt DAZU; nur K3 fittet je Teilklasse neu.

## 7. Offene Entscheidungen für den Betreiber

1. **Stufe 2 jetzt oder erst nach Stufe 1?** Empfehlung: erst Stufe 1.
   Zeigt `frosttage_28` oder `frost_ja_28` nichts, ist auch von
   `tage_seit_erstfrost` innerhalb ±7 Tagen wenig zu erwarten — und die
   App hätte es ohnehin nur mit einem neuen Stationsfeld.
2. **Die Teilung der Klasse (K3) als Kandidat?** Empfehlung: ja, weil
   sie die Frage „zwei Klassen unter einem Namen“ aus #495 direkt
   beantwortet — mit dem Preis von zwei Parametersätzen, wenn sie
   gewinnt.
3. **Ausliefern ohne frische Bestätigung?** Empfehlung: nur unter
   Regel 1–4 (▲ auf Erkundung, alle oder keine, nicht hinter der
   Klimatologie, Gegenprüfung nicht ▼), sichtbar als „experimentell“,
   und mit der Zusage, nach dem Winter 2026/27 nachzumessen.

## Nachtrag 2026-09-21 — Ergebnis Stufe 1 (Labor, Lauf 19)

Freigegeben als „Dann Stufe 1“, gelaufen wie oben festgelegt
(`pilzbuddy-lab/berichte/19-frost-holz-winter.md`): 9 735 Strata der
acht Arten, DACH-Erkundungsblöcke, LOYO, Placebo −0,000 (der Lauf misst,
was er soll).

**Angenommen: keiner.** Kein Frost- oder Mindesttemperatur-Merkmal
gewinnt gesichert gegen das angenommene Logit:

| Kandidat | Δ Log-Lik. gegen K0 (gepaart, OOF) |
|---|--:|
| Frosttage 7 d (bestes Fenster) | +0,002 [−0,000, +0,004] n.s. |
| Frosttage 14 d | −0,001 n.s. |
| Frosttage 21 d | −0,001 ▼ |
| Frost ja/nein 28 d | −0,001 ▼ |
| kälteste Nacht 14 d | −0,000 n.s. |
| Teilung Winter / Holz Sommer-Herbst | +0,001 / −0,002 n.s. |
| Winter-Trio + Frosttage | +0,005 [−0,000, +0,010] n.s. |

Gegenprüfung auf den verbrauchten Testteilen: überall nicht
unterscheidbar.

**Der eine Befund mit Vorzeichen:** Der Koeffizient der Frosttage ist
NEGATIV (−0,08 je Frostnacht). Ein Tag mit mehr Frostnächten davor als
seine Nachbartage ist seltener ein Meldetag; beim Samtfußrübling ist
das gesichert (+0,013 ▲). Nach Frostnächten wird also WENIGER gemeldet
— gefrorene Fruchtkörper, weniger Sammler, oder beides. Die Hypothese
„braucht initial Minustemperaturen“ ist auf der Wochenskala nicht zu
sehen; der saisonale Teil („nach dem ersten Frost beginnt es“) ist der
Kalender, und den trägt seit 1.157.0 das Saison-Tor.

**Folgen:** Stufe 2 (120-Tage-Reihe, Stationsfeld „erster Frost“) wird
nicht empfohlen. Die Klasse bleibt, wie sie in 18 angenommen wurde,
mit einem Parametersatz. Nebenbefund für die Einordnung der Klasse:
Gegen die Klimatologie liegt das angenommene Logit auf den
Erkundungsblöcken OOF bei −0,021 [−0,048, +0,002] (in 18 auf den
Testteilen +0,020 ▲) — der Gewinn gegenüber der 13-°C-Glocke ist real,
der Gewinn gegenüber „nur die Saison“ klein und wackelig. Was die App
an Aussage trägt, kommt zum größeren Teil aus dem Saison-Tor.

## Nachtrag 2, 2026-09-21 — der Verlauf statt des Fensters (Läufe 21 und 22)

Einwand des Betreibers nach Stufe 1: „Wir sollten anhand der Wetterdaten
der Fundtage lernen und nicht Hypothesen blind mit Vergleichstagen
abbilden.“ Also der Verlauf selbst, Tag für Tag vor dem Fund
(`21-frost-verlauf.md`):

- Vor Winter-Fundtagen ist die kälteste Nacht der Tage 1–3 gesichert
  milder als vor den Kontrolltagen (+0,4 bis +0,9 °C ▲, alle drei
  Winterarten), die Tage 14–28 eher kälter. „Milder geworden“ (Tage 1–7
  gegen 8–14) ▲ bei allen drei, exakt null bei den Holz-Arten. Das
  Muster „Frost in 8–28, frostfrei in 1–7“ ist vor Fundtagen um 3–6
  Prozentpunkte häufiger, am stärksten im November und März.
- Warum Stufe 1 das nicht sah: Eine Fensterzählung summiert frischen
  Frost (senkt) und alten Frost (hebt) zu einer Zahl, und die hebt sich
  auf.

Daraus Lauf 22, vorregistriert, Grenzen 5/7/10/14/21 Tage, zwei
Fassungen (zwei Frostspalten; „milder“ = kälteste Nacht Tage 1–b minus
b+1–28) zusätzlich zum angenommenen Logit
(`22-abfolge-holz-winter.md`):

| | gegen das angenommene Logit |
|---|--:|
| ganze Klasse, „milder“ Grenze 5 | +0,004 [−0,002, +0,009] n.s. — **nach Regel nichts angenommen** |
| nur Winter-Trio, „milder“ Grenze 5 / 7 / 10 | +0,011 ▲ / +0,010 ▲ / +0,009 ▲ |
| Samtfußrübling / Judasohr / Austernseitling | +0,025 ▲ / +0,006 ▲ / +0,009 knapp |
| Holz-Sommer/Herbst-Arten | −0,001 |
| Gegenprüfung Testteile, „milder“ 5 | +0,007 ▲ (AT/CH +0,011 ▲) — bestätigt nichts, widerspricht nicht |

Koeffizienten: frischer Frost −0,09 je Nacht, alter Frost +0,03 je
Nacht, milder +0,042 je °C — die Vorzeichen des Verlaufs.

**Folgerung:** Die Klasse „Austernseitling & Co.“ ist ein Kompromiss aus
Winter- und Herbst-Holzarten; ein Merkmal der Winterhälfte kommt
gepoolt nicht durch. Die Frage aus #495, ob das zwei Klassen unter
einem Namen sind, stellt sich damit ein zweites Mal, und diesmal mit
einem Merkmal, das die Trennung begründen würde. Vorschlag: Lauf 23,
eigene Winter-Klasse (Trio) mit Logit + „milder“, vorregistriert,
gleiche Regel. Live-Voraussetzung: 28 Tage `min` in der
Stationstabelle statt 20. Bestätigung weiterhin Winter 2026/27.

## Nachtrag 3, 2026-09-21 — Lauf 23 und der Abschluss der Serie

Eigene Winter-Klasse {Austernseitling, Samtfußrübling, Judasohr} mit
Logit + „milder“ gegen das heutige Klassen-Logit auf den Trio-Strata
(`23-winter-klasse.md`): +0,013 [−0,005, +0,031] — **nach Regel nichts
angenommen.** Die Teilung allein bringt nichts (+0,001) und kostet
Streuung; innerhalb der Teilung trägt das Merkmal gesichert (+0,012 ▲,
Samtfußrübling +0,034 ▲); Placebo 0.

**Serie 19–23 zusammen:** Vor Winter-Fundtagen ist es milder geworden
als vor den Nachbartagen — real, klein, mit denselben Vorzeichen in
Verlauf (21), getrennter Zählung (22) und eigener Klasse (23), rund
+0,01 Log-Likelihood je Stratum. Auf den Erkundungsblöcken reicht das
nicht für ein ▲ nach der Regel; die Testblöcke sind verbraucht.

**Entscheidung, die daraus folgt (Empfehlung):** jetzt nichts
ausliefern. Der Kandidat wird vorab festgeschrieben — Klassen-Logit +
milder_5 (kälteste Nacht Tage 1–5 minus Tage 6–28), aktiv nur für die
drei Winterarten — und einmal auf den Funden des Winters 2026/27
geprüft (GBIF-Download Frühjahr 2027, Funde Nov 2026 – Mär 2027, von
keinem Lauf gesehen), gepaart, gleiche Regel. Trägt er dort, kommt er
in die App, mit 28 Tagen `min` in der Stationstabelle; trägt er nicht,
ist die Frage beantwortet. #497 bleibt als Erinnerung offen.
