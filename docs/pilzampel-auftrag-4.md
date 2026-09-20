# Auftrag 4: Features statt Urteile

Stand: 2026-09-19 · Betreiberentscheidung vom 2026-09-19 · löst
`docs/pilzampel-auftrag-3.md` ab

**Der Anlass ist eine Methodenkritik, und sie trifft.** Bis hierher
wurde jede Frage als registrierter Einzeltest gestellt: eine Latte, ein
Ja oder Nein, eine verbrauchte Prüfachse. Vier Versuche, vier Neins,
drei Achsen. Das ist das richtige Werkzeug, um **eine ausgelieferte
Konstante zu verteidigen**, und das falsche, um **zwanzig Kandidaten zu
vergleichen**.

Phase 3 dreht das um: Erkundung wird stetig bewertet, und nur der
Gewinner bekommt am Ende noch ein binäres Urteil.

---

## 1. Was sich ändert — und was nicht

| | bisher | ab jetzt |
|---|---|---|
| Frage | „Ist Konstante X besser als Y?" | „Welcher Featuresatz trennt am besten?" |
| Antwort | bestanden / nicht bestanden | ein stetiger Score, vergleichbar über alle Kandidaten |
| Kosten je Frage | eine Prüfachse | nichts — dieselben Folds für alle |
| Bestätigung | war die Prüfung selbst | einmal am Ende, auf geschlossenen Daten |

**Was NICHT abgeschafft wird: die Vergleichstage.** Das ist der
wichtigste Punkt dieses Auftrags, und er ist unbequem.

## 2. Warum die Vergleichstage bleiben

Der Einwand des Betreibers: „Niemand weiß, was da wirklich für
Bedingungen vorherrschten." Das stimmt — GBIF kennt nur Funde, kein
„hier war nichts".

Aber das ist kein Messfehler, sondern die Datenlage. **Jedes überwachte
Modell braucht Negativbeispiele**, und eine Aufteilung in Training,
Validierung und Test ändert daran nichts: Sie löst Überanpassung, nicht
das fehlende Nein. Die Alternativen sind schlechter:

- **Zufällige Hintergrundpunkte** lernen den Melder — Wochenende,
  Wegnähe, Stadtnähe, Wanderwetter. Das Modell sagt dann vorher, wann
  Menschen im Wald sind.
- **Zählmodelle** haben dasselbe Problem im Nenner.
- **Case-Crossover** — gleicher Ort, gleiche Jahreszeit, anderes Jahr —
  ist das Verfahren, das sich Ort und Saison herauskürzt, ohne sie
  modellieren zu müssen.

**Die Richtung des Fehlers ist bekannt, und das ist entscheidend.** Wenn
in einem Kontrolljahr ein Pilz stand, den niemand gemeldet hat, wird
dieses Paar fälschlich als „kein Unterschied" gezählt. Das **dämpft**
jedes Signal; es erfindet keines. Was wir finden, ist eher zu klein als
zu groß.

Was wir deshalb **nicht** dürfen: absolute Wahrscheinlichkeiten
behaupten. Was wir dürfen: Kandidaten gegeneinander ranken.

**Der einzige echte Ausweg ist #199** — Begehungen mit „nichts
gefunden" aus der App selbst. Solange die nicht da sind, bleibt jede
Zahl dieser Arbeit relativ.

### 2a. Beide Vergleichsarten zusammen (Betreiber, 2026-09-19)

> „Vielleicht können wir das Beste aus beiden Welten nutzen: Tage im
> selben Jahr davor/danach in einem Fenster, und auch in anderen
> Jahren."

**Angenommen — und es löst ein gemessenes Problem.**

Die beiden Designs haben gegenläufige Schwächen:

| | Kontrast | Kalender |
|---|---|---|
| **A** — 26 bis 45 Tage daneben, selbes Jahr | breit (SD 4,4 K) | steckt drin, rund 0,09 AUC |
| **B** — selbes Datum ±7 d, anderes Jahr | schmal (SD 3,2 K; 60 % der Vergleiche unter ±2 K) | vollständig heraus |

Das schmale Band von B ist nicht bloß unschön, es hat H6 umgebracht:
Um die **Krümmung** einer Glocke zu schätzen, braucht man Temperaturen
über einen weiten Bereich. Auf ±2 K ist das Optimum kaum identifiziert
— daher das 2 K breite Plateau und der 1,84-K-Streit zwischen Gitter
und Logit (`pilzampel-h6-vorpruefung-ergebnis.md`).

**Die Auflösung: beide Arten beim SCHÄTZEN, nur B beim BEWERTEN.**

1. **Anpassen** auf Strata, die **beide** Kontrolltypen enthalten —
   plus einen flexiblen Saisonterm (Spline im Tag-des-Jahres). Die
   A-Kontrollen spannen den Temperaturbereich auf und identifizieren
   den Saisonterm; die B-Kontrollen identifizieren den Wetterterm
   innerhalb der Woche.
2. **Bewerten** ausschließlich auf **B-Strata**. Dort ist die Saison
   innerhalb des Stratums konstant und kürzt sich in der bedingten
   Likelihood heraus — der Saisonterm ist eine Störgröße, die
   geschätzt, aber nicht mitbewertet wird. **Der Kalender kann den
   Score also nicht aufblähen.**

Damit fällt der Einwand gegen A weg, ohne seinen Vorteil zu verlieren.

**Die Pflichtdiagnose, die das ehrlich hält:** Die Wetterkoeffizienten
aus der gemeinsamen Anpassung werden **immer** neben die aus der
B-only-Anpassung gestellt. Stimmen sie überein, tut der Saisonterm
seine Arbeit. Sind die gemeinsamen deutlich größer, tut er sie nicht,
und der Kalender ist durch die Hintertür zurück. Ohne diese Spalte ist
das gemeinsame Design nicht zu verantworten.

**Und eine harte Nebenbedingung:** Der Mindestabstand der A-Kontrollen
muss **mindestens so groß sein wie das längste benutzte Wetterfenster**.
Heute sind es 26 Tage Abstand bei 26 Tagen Fenster — das passt gerade
so. Sobald in der Fenstersuche 35 Tage vorkommen, müssen die
A-Kontrollen auf ≥ 35 Tage Abstand, sonst überlappt das Fenster des
Vergleichstags mit dem des Fundtags und beide teilen sich denselben
Regen.

## 3. Die Aufteilung

**Betreiberauflage vom 2026-09-19: „Ich würde gern den Testteil
möglichst gleichverteilt auswählen, sonst gibt es nur Probleme, wenn die
Datensätze Eigenheiten haben."**

Die Auflage ist berechtigt, und wir haben die Eigenheiten gemessen: Die
Glocke trennt in 2019–2025 schwächer als in 2006–2018
(`pilzampel-alterung.md`), und auf AT+CH ist die Streuung zwischen den
Jahren so groß, dass H6 dort eine nachweisbare Effektgröße von 0,069
hatte — dreimal so viel wie auf P3. Ein Testteil, der aus **einem**
Block besteht, misst dessen Eigenheiten mit.

Zufällig nach Zeilen aufzuteilen geht trotzdem nicht: Eine Exkursion
liefert dreißig Meldungen aus demselben Waldstück derselben Woche.
Landen davon zwanzig im Training und zehn im Test, prüft der Score das
Gedächtnis des Modells.

**Deshalb: geschichtete Blockaufteilung.**

| | Einheit | Regel |
|---|---|---|
| **Block** | ~50-km-Raster über Deutschland | ein Block liegt **ganz** in genau einem Teil |
| **Test** | 20 % der Blöcke | **geschichtet** nach Region und Fundzahl, damit alle Gegenden vorkommen |
| **Erkundung** | die übrigen 80 % | Leave-One-Year-Out-Kreuzvalidierung darin |

Räumlich zu blocken hat einen Nebeneffekt, der hier genau passt: **Ein
Block enthält Funde aus allen Jahren.** Der Testteil ist damit über die
Zeit von selbst gleichverteilt, und gleichzeitig kommt kein Wetter
eines Testblocks je im Training vor.

**Zwei Zahlen, nicht eine.** Die geschichtete Aufteilung beantwortet
„funktioniert es an einem neuen Ort". Die Frage einer App, die in die
Zukunft läuft, ist aber „funktioniert es in der nächsten Saison".
Deshalb wird **immer beides berichtet**:

1. **Hauptscore**: geschichtete Blockaufteilung, wie oben.
2. **Vorwärtsvalidierung**: trainiere bis Jahr J−1, teste Jahr J —
   innerhalb der Erkundungsblöcke, über alle Jahre rollend.

Läuft beides auseinander, ist das selbst der Befund.

**AT + CH bleibt vollständig draußen.** Das ist eine dritte Frage —
„reist es?" — und sie wird einmal ganz am Ende gestellt, getrennt
berichtet und nicht in den Hauptscore gemischt.

**Ehrlich dazugesagt:** Diese Aufteilung ist neu, die Daten sind es
nicht. DE ≥ 2019 ist dreimal befragt worden, AT+CH sechsmal
(`pilzampel-pruefachsen.md`). Die Behauptung lautet deshalb nicht „diese
Daten sind unberührt", sondern: **In Phase 3 wurde auf dem Testteil
nichts ausgewählt.** Das ist schwächer und es ist wahr.

## 4. Der Score

Einheit ist das **Stratum**: ein Fundtag gegen seine k Kontrolltage.

- **Hauptmaß**: Out-of-Sample-Log-Likelihood des bedingten Logits je
  Stratum. Es misst, wie sicher das Modell den richtigen Tag aus k+1
  Kandidaten zieht — und anders als die AUC bestraft es Übermut.
- **Danebengestellt**: die gepaarte AUC (B), damit alle bisherigen
  Zahlen dieser Arbeit anschlussfähig bleiben.
- **Streuung**: über Folds, plus Bootstrap über Fundjahre.

**Pflicht-Baselines, auf denselben Folds, denselben Paaren:**

1. **Klimatologie** — nur Saison, kein Wetter. Zeigt, was der Kalender
   allein kann.
2. **Die ausgelieferte Formel.** Ein neues Modell muss beide schlagen,
   sonst gewinnt das einfachere.

## 5. Features

Aus der Formel, aus der Literatur, und aus dem, was ohnehin im Cache
liegt:

| Familie | Felder | Anmerkung |
|---|---|---|
| Regen | gewichtete Summen, 3/7/14/26/35 d | die heutige Ampel |
| **Bodenfeuchte** | 7–28 cm, dieselben Fenster | roh besser als der Regenfaktor bei 6 von 6 Arten (`pilzampel-bodenfeuchte.md`) |
| Bodentemperatur | 0–7 cm | liegt vollständig im Cache, nie benutzt |
| Lufttemperatur | Mittel, Minimum | quadratisch oder als Spline |
| Frost | Tage seit Frost, Frosttage, Wärmesumme seither | aus H3 übrig |
| Anomalien | Abweichung von der Ortsklimatologie je Tag-im-Jahr | macht Regionen vergleichbar |
| Interaktion | Feuchte × Temperatur | die heutige Formel ist ein Spezialfall davon |

**Der Monat kommt NICHT als Feature hinein.** Im Case-Crossover ist er
innerhalb eines Stratums konstant und kürzt sich heraus — genau dafür
ist das Design da. Ihn in einem anderen Aufbau aufzunehmen, würde ihn
zum stärksten Prädiktor machen, den Score glänzen lassen und alle
Wetterfeatures wertlos aussehen lassen. Das ist derselbe Kalender-Effekt,
der Design A um 0,09 AUC aufgebläht hat, in neuem Gewand. Die Saison
bleibt ein **getrennter Term**, und gemessen wird, was Wetter
**zusätzlich** bringt.

**Fensterlängen werden EINMAL gesucht und dann eingefroren** — auf den
Erkundungsblöcken, nie auf dem Testteil. Wer sie im Modellvergleich
weiter optimiert, hat sie mehrfach ausgewählt und den Score verdorben.

## 6. Die Modellleiter

Nächste Stufe erst, wenn die vorige ausgereizt ist:

| Stufe | Modell | Stand |
|---|---|---|
| 0 | Klimatologie (nur Saison) | Pflicht-Baseline |
| 1 | die ausgelieferte Formel | Pflicht-Baseline |
| 2 | bedingtes Logit, Features linear/quadratisch | **liegt fertig vor** (`tool/ampel_logit.py`) |
| 2a | dasselbe auf A+B-Strata mit Saison-Spline | der Zuschnitt aus 2a — bessere Identifikation des Optimums |
| 3 | bedingtes Logit mit Splines, regularisiert | |
| 4 | Gradient Boosting auf Strata | |
| 5 | alles Rekurrente | **zuletzt, und nur mit Begründung** |

Zu Stufe 5, vorab und nicht verhandelbar: Pro Art rund 2000 Funde,
geklumpt nach Jahr und Melder. Ein rekurrentes Netz hat dort mehr
Parameter als unabhängige Beobachtungen und lernt zuverlässig das
Meldeverhalten. Es steht auf der Leiter, aber ganz oben.

## 7. Wo gearbeitet wird

**Privates Repo `MacBuchi/pilzbuddy-lab`** (Betreiberentscheidung
2026-09-19, Ausgestaltung delegiert). numpy, pandas und scikit-learn
gehören nicht neben eine Flutter-App, deren `tool/` in der CI auf der
Standardbibliothek läuft.

> **Die Grenze:** Was in die App oder in diese Berichte kommt, muss
> allein aus dem öffentlichen Repo nachrechenbar sein.

Das Labor importiert `tool/ampel_validate.py` aus einem Checkout dieses
Repos, statt es zu kopieren — eine zweite Fassung wäre der dritte
Modellkern, den `CLAUDE.md` verbietet, und eine Baseline aus einer
veralteten Kopie wäre keine. Jeder Bericht dort trägt den Commit, gegen
den er gerechnet wurde; ein schmutziger Arbeitsbaum bricht den Lauf ab.

## 8. Was am Ende steht

Ein Modell wird nur ausgeliefert, wenn alles vier gilt:

1. Es schlägt beide Baselines auf den Erkundungsfolds.
2. Es hält auf dem **geschlossenen Testteil** — ein Lauf, Latte vorher
   gesetzt.
3. Es reist nach AT+CH, oder es steht dabei, dass es das nicht tut.
4. Es ist erklärbar genug, dass im Spot-Blatt ein Satz darüber stehen
   kann. Eine Ampel, die niemand begründen kann, ist für diese App
   wertlos — auch wenn sie besser trennt.

Und die Regeln aus Auftrag 2 gelten weiter: Methodenwechsel nach
Datensicht in den Korrekturkasten, Gegenprobe vor jeder Testbehauptung,
nichts an der ausgelieferten Ampel ohne Freigabe.
