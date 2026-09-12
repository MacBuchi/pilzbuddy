# Die Schwellen der Ampel — gemessen

Stand: 2026-09-12 · Erzeugt von `tool/ampel_validate.py --thresholds` · Prüfplan: `docs/pilzampel-schwellen.md`

Die App zeigt drei Stufen. Wo sie liegen, entscheiden zwei Zahlen, die seit der ersten Vorschau als „GESETZT, nicht gemessen“ in `lib/features/ampel/ampel_model.dart` stehen — diese Seite ist ihre erste Messung.

## Vorhersage 1: Welchem Quantil entsprechen 0,2 und 0,5?

Gemessen an den Vergleichstagen der **Anpassjahre**, unter dem **ausgelieferten** Fenster (13 °C) — also an dem, was die App heute rechnet. „Jahresbalanciert“ gibt jedem Jahr dasselbe Gewicht, damit ein gutes Pilzjahr die Schwelle nicht über seine Meldemenge zu sich zieht.

Die letzte Spalte ist eine **Diagnose, keine zweite Antwort**: Gemessen wird auf den Anpassjahren, weil diese Zahlen die Schwellen setzen. Weicht die Prüfjahr-Spalte ab, bedeutet dieselbe feste Zahl in den beiden Zeitscheiben etwas Verschiedenes — die Schwelle altert dann mit dem Wetter, und zwar im ausgelieferten Binary.

| Art | 0,2 entspricht | 0,5 entspricht | 0,2 balanciert | 0,5 balanciert | 0,5 auf den Prüfjahren |
|---|--:|--:|--:|--:|--:|
| Steinpilz | 42,1 % | 72,6 % | 41,2 % | 72,6 % | 80,3 % |
| Maronenröhrling | 38,2 % | 72,9 % | 37,7 % | 67,5 % | 79,5 % |
| Pfifferling | 30,1 % | 62,9 % | 32,9 % | 65,6 % | 74,1 % |
| Birkenpilz | 42,2 % | 74,9 % | 44,0 % | 76,4 % | 81,6 % |
| Fichtenreizker | 39,0 % | 65,8 % | 43,5 % | 71,9 % | 74,6 % |
| Herbsttrompete | 30,7 % | 62,0 % | 38,3 % | 63,7 % | 81,0 % |

**Median über die sechs Mykorrhiza-Arten** (jahresbalanciert): 0,2 liegt bei **39,7 %**, 0,5 bei **69,7 %**.

Registriert war: 45 %–55 % und 75 %–85 %.

**Ergebnis: NICHT bestätigt.** Der Median liegt unter dem registrierten Band.

Auf den **Prüfjahren** liegt er dagegen bei **79,9 %** — und daher kam die Erwartung: Sie war aus dem Stufenvergleich abgeleitet, und der rechnet auf Prüfjahren. Zwischen den beiden Zeitscheiben liegen im Median **+8,1 pp**, bei allen sechs Arten in dieselbe Richtung.

Damit ist die eigentliche Auskunft dieser Tabelle nicht das Quantil, sondern: **Dieselbe feste Zahl bedeutet in den beiden Hälften der Daten etwas Verschiedenes.** Die ausgelieferte 0,5 ist heute eine strengere Schwelle als zur Zeit ihrer Festlegung — ohne dass je eine Zeile Code geändert wurde. Ob dahinter das Wetter steckt oder eine gewachsene GBIF-Stichprobe, trennt diese Messung nicht; für die App ist die Folge dieselbe.

Und für die Quantile heißt es: Sie sind hier eine **Entscheidung darüber, wie oft die Ampel günstig steht**, und keine Kalibrierung auf einen vorgefundenen Wert. Gerundet wurde trotzdem nur einmal und nur an diesen sechs Arten — die Alternative wäre gewesen, so lange zu runden, bis Vorhersage 2 durchgeht.

## Die Schwellen, die daraus folgen

Gesetzt auf **40 %** (verhalten) und **70 %** (günstig) der Vergleichstage, je Art unter ihrem eigenen Fenster und auf den Anpassjahren bestimmt.

| Art | Optimum | verhalten ab | günstig ab |
|---|--:|--:|--:|
| Steinpilz | 13.0 °C | 0.195 | 0.458 |
| Maronenröhrling | 13.0 °C | 0.206 | 0.547 |
| Pfifferling | 17.5 °C | 0.254 | 0.707 |
| Birkenpilz | 14.5 °C | 0.198 | 0.533 |
| Fichtenreizker | 12.0 °C | 0.157 | 0.519 |
| Herbsttrompete | 13.0 °C | 0.234 | 0.566 |
| Hallimasch | 11.0 °C | 0.117 | 0.336 |
| Stockschwämmchen | 12.2 °C | 0.123 | 0.306 |
| Austernseitling | -3.2 °C | 0.000 | 0.005 |

## Was die Nutzerin sähe

Der **Abstand** zwischen „günstig an Fundtagen“ und „günstig an Vergleichstagen“, auf den Prüfjahren. Er ist das, was eine Stufe wert ist: Stünde sie an beiden gleich oft, sagte sie nichts.

**Und er hängt daran, WO die Schwelle liegt.** Er ist null, wenn „günstig“ nie oder immer gilt, und am größten irgendwo dazwischen — eine strengere Schwelle kann ihn also verkleinern, ohne dass das Modell schlechter wäre. Die schwellenfreie Aussage steht als AUC in `docs/pilzampel-artenfenster-messung.md`; diese Seite fragt bewusst das andere: was die Nutzerin sieht.

| Art | heute | nur eigenes Fenster | Fenster **und** Schwellen | günstig an Fundtagen | an Vergleichstagen |
|---|--:|--:|--:|--:|--:|
| Steinpilz | +38,1 pp | +38,1 pp | **+41,0 pp** [+30,1, +50,9] | 58,4 % → **63,6 %** | 20,3 % → 22,6 % |
| Maronenröhrling | +32,3 pp | +32,3 pp | **+29,3 pp** [+17,5, +40,4] | 52,6 % → **47,1 %** | 20,3 % → 17,8 % |
| Pfifferling | +12,3 pp | +18,9 pp | **+14,6 pp** [+10,5, +20,9] | 37,7 % → **36,4 %** | 25,4 % → 21,8 % |
| Birkenpilz | +32,6 pp | +32,8 pp | **+28,6 pp** [+22,3, +38,0] | 51,6 % → **45,3 %** | 18,9 % → 16,7 % |
| Fichtenreizker | +31,1 pp | +34,3 pp | **+34,9 pp** [+24,6, +43,6] | 56,6 % → **56,3 %** | 25,5 % → 21,4 % |
| Herbsttrompete | +22,9 pp | +22,9 pp | **+16,0 pp** [+4,3, +31,1] | 42,4 % → **33,3 %** | 19,4 % → 17,4 % |
| Hallimasch | +36,7 pp | +47,8 pp | **+53,2 pp** [+39,1, +65,5] | 54,5 % → **80,1 %** | 17,8 % → 26,9 % |
| Stockschwämmchen | +34,1 pp | +37,3 pp | **+44,0 pp** [+37,3, +50,9] | 50,3 % → **72,9 %** | 16,2 % → 28,9 % |
| Austernseitling | -0,2 pp | +0,5 pp | **+8,1 pp** [+0,9, +15,8] | 21,7 % → **42,2 %** | 21,8 % → 34,2 % |

## Vorhersage 2: der Austernseitling

> Mit Quantil-Schwellen liegt der Abstand beim Austernseitling bei mindestens **+10 pp**, gegenüber +0,5 pp mit den festen Schwellen.

Gemessen: **+8,1 pp** [+0,9 pp, +15,8 pp] — „günstig“ an Fundtagen 21,7 % → **42,2 %**, an Vergleichstagen 21,8 % → 34,2 %.

**Ergebnis: Schwelle verfehlt — der Effekt ist aber da.** Der Abstand ist von praktisch null auf +8,1 pp gestiegen, und sein Bereich schließt die Null aus; die vorab gesetzte Latte von +10 pp hat er trotzdem nicht genommen. Beides gehört nebeneinander berichtet: Die Richtung stimmt, die Größe war zu optimistisch angesagt.

**Und die Latte hing an einer Zahl, die selbst unsicher ist.** Wie groß der Abstand ausfällt, hängt am gewählten Quantil — und dessen Wahl ist nach Vorhersage 1 keine vorgefundene Größe mehr, sondern eine Entscheidung. Eine Latte in Prozentpunkten war dafür das falsche Maß; sie unterstellt eine Schwelle, die feststeht.

## Was ausgeliefert würde

**Betreiberentscheidung 2026-09-12: „gleich häufig vorerst.“** Die Umstellung soll die Treffsicherheit ändern, nicht zugleich, wie oft die Ampel überhaupt spricht; beides auf einmal machte hinterher unauswertbar, was gewirkt hat.

Daraus folgen die Quantile **50 %** (verhalten) und **80 %** (günstig) — der Median der sechs ausgelieferten Arten auf den **Prüfjahren**, also dort, wo die App heute steht. Auf den Anpassjahren zu kalibrieren wäre hier falsch: Die Ampel käme um die gemessene Drift zu großzügig heraus.

| Art | Optimum | verhalten ab | günstig ab | günstig an Vergleichstagen |
|---|--:|--:|--:|--:|
| Steinpilz | 13.0 °C | 0.189 [0.148, 0.238] | 0.493 [0.439, 0.531] | 20,1 % |
| Maronenröhrling | 13.0 °C | 0.192 [0.147, 0.238] | 0.510 [0.476, 0.531] | 20,1 % |
| Pfifferling | 17.5 °C | 0.287 [0.228, 0.367] | 0.677 [0.560, 0.760] | 20,0 % |
| Birkenpilz | 14.5 °C | 0.222 [0.186, 0.274] | 0.469 [0.408, 0.505] | 20,1 % |
| Fichtenreizker | 12.0 °C | 0.196 [0.143, 0.234] | 0.539 [0.510, 0.577] | 20,4 % |
| Herbsttrompete | 13.0 °C | 0.161 [0.089, 0.284] | 0.445 [0.287, 0.624] | 20,3 % |
| Hallimasch | 11.0 °C | 0.154 [0.125, 0.178] | 0.403 [0.366, 0.420] | 20,1 % |
| Stockschwämmchen | 12.2 °C | 0.165 [0.122, 0.192] | 0.417 [0.384, 0.440] | 20,0 % |
| Austernseitling | -3.2 °C | 0.001 [0.000, 0.001] | 0.037 [0.017, 0.057] | 20,1 % |

Die letzte Spalte ist **keine Messung, sondern die Probe aufs Exempel**: Sie muss auf eine Beobachtung genau bei 20 % herauskommen, weil die Schwelle genau so gesetzt wurde. Steht dort etwas anderes, ist die Rechnung kaputt.

**Und diese Zahlen verfallen.** Sie beschreiben die Verteilung der Jahre ab 2019; die Messung oben zeigt, dass sich genau diese Verteilung über ein Jahrzehnt um gut acht Prozentpunkte verschoben hat. Wer sie ausliefert, schreibt das Datum dazu und misst nach.

## Die Klassen

**Die Einheit ist die Klasse, nicht die Art** (Betreiber, 2026-09-12). Eine Klasse ist ein Temperaturfenster; die beiden Schwellen fallen daraus, als Quantile der Verteilung, die dieses Fenster an Vergleichstagen erzeugt. Zusammengelegt wird so, dass **jede Art gleich viel zählt** — ungewichtet wäre die Herbstschwelle die Steinpilzschwelle mit anderem Namen.

| Klasse | Fenster | verhalten ab | günstig ab | Arten | ausgeliefert |
|---|--:|--:|--:|---|---|
| sommer | 17.5 °C | 0.287 | 0.677 | Pfifferling | ja |
| herbst | 13.0 °C | 0.187 | 0.512 | Steinpilz, Maronenröhrling, Birkenpilz, Fichtenreizker, Herbsttrompete | ja |
| herbst_holz | 11.6 °C | 0.149 | 0.408 | Hallimasch, Stockschwämmchen | **nein** |
| kalt | -3.2 °C | 0.001 | 0.037 | Austernseitling | **nein** |

Die Spalte „ausgeliefert“ ist die eigentliche Grenze: Aufgenommen wird nur, was einen **Hold-out** bestanden hat. „Sieht in der Tabelle anders aus“ reicht nicht — daran wäre die Pfifferling-Spur fast gescheitert, bis Österreich und die Schweiz sie bestätigt haben. Für die übrigen gilt bis dahin, was für jede ungeprüfte Art gilt: lieber grau als erfunden.
- **sommer** — Hold-out in AT+CH bestätigt: AUC 0,584 → 0,689 (+0,104 [+0,055, +0,150]), abstandsgleiche Kontrolle 0,510 (docs/pilzampel-artenfenster-holdout.md)
- **herbst** — der ausgelieferte Stand; die eigenen Optima dieser fünf liegen zwischen 12,0 und 14,5 °C, und keine Abweichung von 13 °C schließt die Null aus
- **herbst_holz** — nach dem Blick auf die Tabelle ausgewählt — dieselbe Lage wie beim Pfifferling vor seinem Hold-out
- **kalt** — Fenster gemessen, aber in Stufen unter der registrierten Latte; der Kalttest (Judasohr, Samtfußrübling) steht aus

## Läuft das Fenster mit der Fruchtungszeit?

Die registrierte Zusatzprüfung aus `docs/pilzampel-artenfenster.md` — und die Grundlage für die Frage, ob Arten **ohne** eigene Messung einer Klasse zugeordnet werden können. Die Saisonkurven sind an keiner Anpassung beteiligt: Sie kommen aus GBIF-Meldemonaten, die Fenster aus Wetterreihen.

Der mittlere Fruchtungsmonat wird auf dem **Kreis** gebildet. Linear gemittelt landet der Austernseitling mit seinem Dezembergipfel im Juni, also genau zwischen seinen beiden Enden — und die Korrelation fällt von −0,68 auf −0,07. Die „Schärfe“ ist die Länge des Summenvektors: 1 heißt „alles in einem Monat“, 0 heißt „über das Jahr verteilt“.

| Art | mittlerer Monat | Schärfe | Optimum |
|---|--:|--:|--:|
| Pfifferling | 7.6 | 0.69 | 17.5 °C |
| Stockschwämmchen ⚠ | 7.9 | 0.29 | 12.2 °C |
| Steinpilz | 8.6 | 0.73 | 13.0 °C |
| Birkenpilz | 8.7 | 0.72 | 14.5 °C |
| Fichtenreizker | 9.1 | 0.73 | 12.0 °C |
| Maronenröhrling | 9.3 | 0.71 | 13.0 °C |
| Herbsttrompete | 9.3 | 0.74 | 13.0 °C |
| Hallimasch | 10.5 | 0.76 | 11.0 °C |
| Austernseitling | 12.8 | 0.76 | -3.2 °C |

**Spearman über alle 9: -0,678**

Ohne Kurven unter Schärfe 0,35 (Stockschwämmchen — eine flache Kurve hat keine Saison, über die sich korrelieren ließe): **-0,830** bei n=8

**Diese Schwelle ist NACH dem Blick auf die Daten gesetzt**, und das gehört dazugesagt. Was für sie spricht: Die Lücke ist breit (0,29 gegen 0,69), es liegt keine einzige Art dazwischen, und „flach“ ist eine Eigenschaft der Kurve allein — sie kennt das Optimum nicht. Was gegen sie spricht: Sie ist trotzdem eine Entscheidung, die die Zahl verbessert hat.

**Was die Zahl trägt — und was nicht.** Die Rangfolge hält: Sommerfrüchter warm, Herbstarten um 13 °C, Winterfrüchter kalt. Der ZUSAMMENHANG ist aber nicht linear — von 9,3 auf 10,5 Monate fällt das Optimum um 2 K, von 9,3 auf 12,8 um 16. Eine Gerade durch diese Punkte zu legen und damit einer Art eine Gradzahl zuzuweisen wäre erfunden; sie einer **Klasse** zuzuordnen ist es nicht.


## Was diese Seite NICHT sagt

Sie ändert `ampel_model.dart` nicht. Über eine Umstellung entscheidet der Betreiber mit diesen Zahlen; bis dahin bleibt der Gleichlauf „Zahl für Zahl“ zwischen Modellkern und Werkzeug unberührt.

Und die Grenze des Konzeptpapiers gilt unverändert: Auch eine kalibrierte Schwelle sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
