# H1 registriert: schmalere Temperaturglocke (3,25 K statt 5 K)

Stand: 2026-09-18 · Auftrag: `docs/pilzampel-auftrag-2.md` Abschnitt 4,
in der Fassung von `docs/pilzampel-auftrag-2-nachtrag-1.md` N5 ·
Vorlauf: `docs/pilzampel-kontrolldesign.md`

**Diese Seite wird VOR dem Lauf geschrieben und danach nicht mehr
angefasst.** Was hier nicht steht, entscheidet nichts. Das Ergebnis kommt
in eine eigene Datei.

---

## 1. Was geprüft wird — genau eine Zahl

Die Temperaturglocke der Ampel ist

    exp( −((T̄₂₀ − Optimum) / σ)² )

mit σ = **5,0 K** (`TEMP_SIGMA` in `tool/ampel_validate.py`,
`ampelTempSigma` in `lib/features/ampel/ampel_model.dart`). Diese Breite
ist **gesetzt, nicht gemessen** — das Bielefelder Papier nennt einen
Gipfel, keine Streuung.

Geprüft wird **σ = 3,25 K** gegen **σ = 5,0 K**, sonst nichts.

Die 3,25 K stammen aus der Nachrechnung der öffentlichen Bielefelder
Tagesdaten (`scripts/bielefeld_refit.py` im Skill `datenanalyse`), also
aus einer Quelle, die mit GBIF nichts zu tun hat. **Deshalb sind alle
GBIF-Jahre Prüfdaten** und nicht nur die Jahre ab 2019.

### σ ist EINE Konstante für beide ausgelieferten Klassen

Das ist der Punkt, an dem H1 sich von den bisherigen Klassenfragen
unterscheidet. Optimum und Schwellen hängen an der Klasse; σ hängt an
keiner. Herbstklasse und Sommerklasse rechnen heute mit derselben
Breite.

Daraus folgt die Urteilsregel weiter unten: **Die Breite wird nur
geändert, wenn beide ausgelieferten Klassen bestehen.** Ein σ je Klasse
wäre ein neuer Freiheitsgrad, den niemand registriert hat — und der Weg
dorthin führt über eine eigene Registrierung, nicht über dieses
Ergebnis.

## 2. Was ausdrücklich NICHT geprüft wird

- **Das Optimum wird nicht mitangepasst.** Herbst bleibt bei 13,0 °C,
  Sommer bei 17,5 °C. Phase 0.4 hat gezeigt, dass angepasste Optima auf
  wenigen hundert Paaren um bis zu 3 K wandern und den Instrumentwechsel
  nicht überstehen. Zwei freie Größen auf einmal machen den Test
  unlesbar.
- **Es wird kein σ-Gitter gesucht.** Genau ein Wert gegen genau einen
  Amtsinhaber. Ein Gitter machte aus der externen Zahl eine angepasste,
  und damit wäre die Begründung „alle GBIF-Jahre sind Prüfdaten"
  hinfällig.
- **Keine Schwellen, kein Dart-Code, keine Ausgabe.** Auch bei Bestehen
  nicht: Die neuen Schwellen werden dann gemessen und als
  Produktentscheidung vorgelegt (Auftrag 2, Abschnitt 5).
- **Keine der anderen Hypothesen.** H2 kommt nach H1, weil beide
  denselben Score verändern.

## 3. Die Daten

Messbasis `pinned`, Entdoppeln an, Design B (gleicher Ort, gleiches
Datum ±7 Tage, fünf Kontrolljahre), Seed 42 — alles wie in Phase 1.5.
**Beide Breiten laufen auf denselben Paaren.** Gezogen wird einmal;
danach wird jeder Fund zweimal bewertet. Ein zweiter Zug machte den
Unterschied teils zur Stichprobe.

Drei Panels, vorab festgelegt:

| Panel | Jahre / Länder | Rolle |
|---|---|---|
| **P1 — entscheidend** | DE 2019–2025 | trägt das Urteil |
| **P2 — Reisetest, bindend als Ausschluss** | AT + CH, alle Jahre | darf nicht widersprechen |
| **P3 — nachrichtlich** | DE 2006–2018 | entscheidet nichts |

**Warum nicht einfach „alle DE-Jahre", wie N5 es erlauben würde.** Für
die Herbstklasse wäre das sauber — 13,0 °C ist extern. Für die
Sommerklasse nicht: Ihre 17,5 °C wurden auf **DE ≤ 2018** angepasst
(`docs/pilzampel-artenfenster-messung.md`) und in AT+CH geprüft. Eine
neue Breite auf denselben Jahren zu messen, auf denen das Optimum
gefunden wurde, prüfte teils die Anpassung mit. P1 und P2 sind für beide
Klassen frei davon.

Das ist **strenger als N5 verlangt**, und es kostet Stichprobe. Wenn der
Betreiber lieber alle DE-Jahre als P1 hätte, ist das eine Zeile im
Befehl — aber sie muss vor dem Lauf fallen, nicht danach.

### Die Arten

| Klasse | Arten | Optimum |
|---|---|--:|
| `herbst` | Steinpilz, Maronenröhrling, Birkenpilz, Fichtenreizker, Herbsttrompete | 13,0 °C |
| `sommer` | Pfifferling | 17,5 °C |

Hallimasch, Stockschwämmchen, Austernseitling, Judasohr und
Samtfußrübling laufen **nachrichtlich mit** — ihre Paare liegen im
Cache, die Zahl kostet nichts. Sie entscheiden nichts: Ihre Klassen sind
nicht ausgeliefert, und nach Phase 1.5 steht für alle fünf „keine
Aussage".

## 4. Das Maß

Für jeden Fund der Anteil der Kontrolljahre, die er schlägt
(Gleichstand 0,5); über die Funde gemittelt — dieselbe Größe wie in
Phase 1.5 (`score_b`).

    Δ = B(σ = 3,25) − B(σ = 5,0)

auf denselben Funden. Der Bootstrap zieht über das **Fundjahr** und
zwar **die Differenz**, nicht die beiden Werte getrennt: Sie teilen sich
jeden einzelnen Fund, und getrennt gezogen wäre das Band weit breiter,
als die Frage es hergibt.

## 5. Die Bedingung

Eine Art besteht, wenn **alle vier** Punkte zutreffen:

| # | Bedingung | Schwelle |
|---|---|---|
| 1 | Δ auf P1 | **≥ +0,020** |
| 2 | Bootstrap der Differenz über Fundjahre, 20 000 Züge | p < 0,025, Band ohne die Null |
| 3 | Anteil der Fundjahre mit Δ_Jahr > 0 | **≥ 70 %** |
| — | Fundjahre, die dabei zählen | ≥ 10 Funde, sonst kein Vorzeichen |
| 4 | Placebo B unter σ = 3,25 | innerhalb 2 SE von 0,50 |
| — | Funde in Design B auf P1 | ≥ 150, sonst „zu dünn" und **kein Urteil** |

Bedingungen 1 bis 3 sind die Standardlatte aus dem Fahrplan, auf Design
B übertragen. Bedingung 4 ist die Kontrolle: Eine neue Glockenbreite
darf das Placebo nicht bewegen, denn dort stehen zwei Nicht-Fundjahre
gegeneinander.

### Das Klassenurteil: alle oder keine

Eine Klasse besteht, wenn **jedes urteilsfähige Mitglied** besteht. Das
ist die Regel, an der am 2026-09-13 die Herbst-Holz-Klasse und die
Kaltklasse gescheitert sind, und sie gilt hier unverändert: Ein sauber
gemessener Fehlschlag eines Mitglieds entscheidet, auch wenn ein anderes
glänzt. „Zu dünn" ist kein Fehlschlag, sondern kein Urteil.

**Die Breite wird nur geändert, wenn `herbst` UND `sommer` bestehen** —
siehe Abschnitt 1. Besteht nur eine, bleibt σ bei 5,0, und der Befund
wird als Anlass für eine eigene Registrierung notiert.

### P2 kann das Bestehen kippen, aber nicht herstellen

Auf AT+CH gilt die +0,02-Latte **nicht** — die Stichprobe ist dort
dünner, und eine dünne Zahl darf keine dicke schlagen. Bindend ist nur
der Ausschluss:

> Schließt das Bootstrap-Band von Δ auf P2 die Null aus und liegt es
> **unterhalb** von null, hat die Klasse nicht bestanden, unabhängig
> von P1.

Der Grund steht in `docs/pilzampel-kaltklasse-holdout.md`: Eine Klasse,
die in Deutschland besteht und im Ausland umkippt, reist nicht — und
ausgeliefert wird nach DACH.

## 6. Gegenproben, die vor dem Urteil laufen müssen

- **Placebo B unter beiden Breiten.** Es misst zwei Nicht-Fundjahre
  gegeneinander und muss bei 0,50 bleiben. Verschiebt es sich mit σ,
  ist der Unterschied kein Signal, sondern ein Artefakt der Ziehung.
- **Die Umkehrprobe:** dieselbe Rechnung mit σ = 8,0 K, also einer
  **breiteren** Glocke. Ergibt auch die ein Δ ≥ +0,02, misst das
  Verfahren nicht die Breite, sondern irgendetwas anderes. Diese Zahl
  entscheidet nichts, aber sie muss im Bericht stehen.
- **Der Selbsttest des Werkzeugs** läuft netzfrei und ist
  gegengeprobt — jede neue Zusicherung war einmal absichtlich rot.

## 7. Diagnosen, die berichtet werden und nichts entscheiden

Vorab festgelegt, damit sie hinterher nicht als Erklärung erfunden
wirken:

- **Wieviel Temperatur, wieviel Regen.** B nur aus dem Temperaturfaktor
  und B nur aus dem Regenfaktor, als **Obergrenzen**: „so weit käme die
  Temperatur allein". Wenn Δ positiv ist, soll ablesbar sein, ob das
  Modell besser trennt oder nur näher an die Temperatur allein
  heranrückt.
- **Der Anteil toter Funde.** Bei sehr schmaler Glocke laufen Scores
  weit vom Optimum gegen null, und dann trägt der Regen nichts mehr bei.
  Gezählt wird der Anteil der Funde, bei denen **jeder** Vergleich
  beidseitig unter 10⁻⁶ liegt. Steigt er deutlich, heißt ein Δ nahe null
  „das Modell hat aufgehört zu unterscheiden" und nicht „kein Effekt".

> **Zwei Korrekturen an diesem Abschnitt, vor dem ersten gemessenen
> Wert.** Beide kommen aus Gegenproben am Werkzeug, die grün blieben,
> wo sie hätten rot werden müssen — und beide betreffen nur Diagnosen,
> die nichts entscheiden.
>
> 1. Hier stand „B nur aus dem Temperaturfaktor, **je Breite**". Das
>    kann es nicht geben: Das Maß ist rangbasiert, und die Glocke fällt
>    für jedes σ > 0 streng monoton mit dem Abstand zum Optimum. B auf
>    der Temperatur allein ist damit **von σ unabhängig**. Es ist eine
>    Obergrenze, kein Vergleich. Der Selbsttest rechnet die
>    Unabhängigkeit nach, damit niemand später eine Differenz sucht, die
>    es nicht geben kann.
> 2. Hier stand „Anteil der Funde mit beat_fraction genau 0,5". Exakte
>    Gleichstände kommen in Fließkomma praktisch nicht vor: `exp(−209)`
>    ist 1e−91 und nicht null, zwei völlig tote Tage gelten dem Rechner
>    also als verschieden. Gezählt wird deshalb gegen 10⁻⁶. Der exakte
>    Gleichstand bleibt als Zahl im Bericht stehen — damit sichtbar ist,
>    dass er nichts trägt.
- **Die mittlere 20-Tage-Temperatur am Fundtag je Art**, gegen 13 bzw.
  17,5 °C. Sie sagt, wem eine schmalere Glocke überhaupt nützen kann.
- **Design A daneben**, weil die bisherigen Zahlen dort stehen. Es
  entscheidet nichts (N5: maßgeblich ist Design B).

## 8. Das bedingte Logit — Information, nicht der Prüfwert

Getrennt vom Test und ausdrücklich **nicht** entscheidend (N5): ein
bedingtes Logit auf den B-Paaren der **Anpassjahre DE ≤ 2018** mit den
Merkmalen `[log R, T̄₂₀, T̄₂₀²]`. Daraus

    Optimum = −b_T / (2 b_T²)      Breite = sqrt( b_logR / −b_T² )

jeweils mit Standardfehler. Der Zweck ist, dass eine flache Likelihood
**sichtbar** wird, statt sich als scheinpräziser Gitterpunkt zu tarnen.

**Wer daraus den Prüfwert macht, verwandelt eine externe Zahl in eine
angepasste** — und deren Instabilität war der Befund aus Phase 0.4. Das
Logit läuft deshalb auf den Anpassjahren, nicht auf P1 oder P2, und
seine Breite wird in diesem Lauf nirgends gegen etwas geprüft.

## 9. Was bei welchem Ausgang passiert

| Ausgang | Folge |
|---|---|
| **Beide Klassen bestehen** | σ = 3,25 wird vorgeschlagen. Vorher: Schwellen neu messen, Evidenzstufen neu vergeben, beides dem Betreiber vorlegen. Kein Dart-Code ohne Freigabe. |
| **Eine besteht, eine nicht** | σ bleibt 5,0. Der Befund wird dokumentiert; ein σ je Klasse braucht eine eigene Registrierung. |
| **Keine besteht** | σ bleibt 5,0, H1 ist geschlossen. Das Ergebnis wird berichtet, nicht weggeräumt. |
| **Δ deutlich negativ** | Ebenfalls ein Ergebnis: Die gesetzten 5 K sind besser als die externe Zahl. Gehört in `docs/pilzampel-konzept.md`. |
| **Gleichstandsanteil explodiert** | Kein Urteil für die betroffene Art; die Messung kann die Frage dort nicht beantworten. |

In jedem Fall gilt Abschnitt 6 des Auftrags: **Kein Rückbau der
ausgelieferten Ampel ohne Freigabe.**

## 10. Der Lauf

```
python3 tool/ampel_diagnose.py --h1 \
    --dataset pinned --dedupe \
    --api http://127.0.0.1:8080/v1/archive \
    --cache ~/pilzbuddy-ampel2000/ampel_cache_pinned \
    --seed 42 \
    --out docs/pilzampel-h1-ergebnis.md
```

Festgenagelt und nicht verhandelbar nach dem Lauf: Datensatz `pinned`,
Entdoppeln an, Seed 42, fünf Kontrolljahre, ±7 Tage Streuung,
20 000 Bootstrap-Züge, die Artenliste aus Abschnitt 3, σ ∈ {5,0; 3,25;
8,0}, die Panels aus Abschnitt 3.

**Der Hold-out-Kontakt, den dieser Lauf verbraucht:** AT+CH für die
Frage „reist eine schmalere Glocke". Diese Achse ist danach für H1
verbraucht. DE 2019–2025 war für die Glockenbreite bisher unberührt und
ist es nach diesem Lauf nicht mehr.

## 11. Was diese Registrierung nicht kann

Design B misst gegen **dasselbe Datum anderer Jahre am selben Ort**, und
„üblich" schließt die guten Jahre ein, weil Presence-only Abwesenheit
nicht kennt. Das dämpft jede Zahl hier, unter beiden Breiten gleich —
für eine Differenz ist es deshalb unkritisch, für die absoluten Werte
nicht.

Und sie prüft eine Form, keine Biologie: Dass eine Glocke mit σ = 3,25
besser trennt, hieße nicht, dass Steinpilze bei 9,75 °C auf ein Drittel
fallen. Es hieße, dass die Rangfolge der Tage damit besser stimmt.
