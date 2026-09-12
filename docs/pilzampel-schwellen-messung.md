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
| Steinpilz | 13.0 °C | 0.189 | 0.493 | 20,1 % |
| Maronenröhrling | 13.0 °C | 0.192 | 0.510 | 20,1 % |
| Pfifferling | 17.5 °C | 0.287 | 0.677 | 20,0 % |
| Birkenpilz | 14.5 °C | 0.222 | 0.469 | 20,1 % |
| Fichtenreizker | 12.0 °C | 0.196 | 0.539 | 20,4 % |
| Herbsttrompete | 13.0 °C | 0.161 | 0.445 | 20,3 % |
| Hallimasch | 11.0 °C | 0.154 | 0.403 | 20,1 % |
| Stockschwämmchen | 12.2 °C | 0.165 | 0.417 | 20,0 % |
| Austernseitling | -3.2 °C | 0.001 | 0.037 | 20,1 % |

Die letzte Spalte ist **keine Messung, sondern die Probe aufs Exempel**: Sie muss auf eine Beobachtung genau bei 20 % herauskommen, weil die Schwelle genau so gesetzt wurde. Steht dort etwas anderes, ist die Rechnung kaputt.

**Und diese Zahlen verfallen.** Sie beschreiben die Verteilung der Jahre ab 2019; die Messung oben zeigt, dass sich genau diese Verteilung über ein Jahrzehnt um gut acht Prozentpunkte verschoben hat. Wer sie ausliefert, schreibt das Datum dazu und misst nach.

## Was diese Seite NICHT sagt

Sie ändert `ampel_model.dart` nicht. Über eine Umstellung entscheidet der Betreiber mit diesen Zahlen; bis dahin bleibt der Gleichlauf „Zahl für Zahl“ zwischen Modellkern und Werkzeug unberührt.

Und die Grenze des Konzeptpapiers gilt unverändert: Auch eine kalibrierte Schwelle sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
