# Diagnosen ohne neues Modell

Stand: 2026-09-17 · Erzeugt von `tool/ampel_diagnose.py --all` · Arbeitsplan: `docs/pilzampel-fahrplan.md`, Phase 1

Gerechnet wird **ausschliesslich auf Deutschland und den Jahren bis 2018**. Nichts hier ist ein Test: Es wird keine Bedingung geprueft und keine Hypothese entschieden. Was hier steht, liefert die Startbereiche fuer Phase 2 — und zwar so, dass der Hold-out unberuehrt bleibt.

Messbasis: `pinned`, Entdoppeln an (`docs/pilzampel-messbasis.md`).


## 1.1 Richtungs-Split — Niveau oder Aenderung?

Gepaarte AUC, getrennt danach, ob der Vergleichstag **vor** oder **nach** dem Fundtag liegt. Beide Haelften stammen aus derselben Ziehung; nur die Seite unterscheidet sie.

Aehnliche Werte heissen: Das Modell reagiert auf das **Niveau** der Bedingungen. Eine deutliche Asymmetrie heisst: Es reagiert auf eine **Aenderung** — dann waere ein Sturz- oder Frostterm die richtige Erweiterung und nicht eine engere Glocke.

| Art | Gruppe | Paare | AUC gesamt | Vergleichstag vor | danach | Differenz |
|---|---|--:|--:|--:|--:|--:|
| Steinpilz | herbst | 951 | 0.737 | 0.754 (508) | 0.718 (443) | -0.036 |
| Maronenröhrling | herbst | 876 | 0.718 | 0.666 (473) | 0.779 (403) | +0.113 |
| Birkenpilz | herbst | 621 | 0.739 | 0.722 (313) | 0.756 (308) | +0.034 |
| Fichtenreizker | herbst | 393 | 0.756 | 0.707 (198) | 0.805 (195) | +0.098 |
| Herbsttrompete | herbst | 147 | 0.735 | 0.708 (72) | 0.760 (75) | +0.052 |
| Pfifferling | sommer | 711 | 0.643 | 0.446 (370) | 0.856 (341) | +0.410 |
| Hallimasch | holz | 921 | 0.705 | 0.618 (498) | 0.806 (423) | +0.188 |
| Stockschwämmchen | holz | 583 | 0.719 | 0.670 (300) | 0.770 (283) | +0.100 |
| Austernseitling | kalt | 361 | 0.637 | 0.840 (194) | 0.401 (167) | -0.439 |
| Judasohr | kalt | 665 | 0.585 | 0.536 (349) | 0.639 (316) | +0.103 |
| Samtfußrübling | kalt | 322 | 0.773 | 0.828 (209) | 0.673 (113) | -0.155 |

### Was da steht

**Bei den Herbstarten ist die Asymmetrie klein** (−0,04 bis +0,11). Das
Modell reagiert dort auf das NIVEAU: Ob der Vergleichstag vier Wochen
vorher oder nachher liegt, ändert wenig.

**Bei vier Arten ist sie riesig** — Pfifferling +0,410, Austernseitling
−0,439, Hallimasch +0,188, Samtfußrübling −0,155. Und der Fahrplan legt
für solche Fälle die Deutung „Reaktion auf Änderung" nahe. **Die trägt
hier nicht**, und die Zahlen sagen selbst, warum:

Beim Pfifferling steht auf der Seite „vor" eine AUC von **0,446** — unter
0,50. Das heißt: Ein Tag vier Wochen VOR dem Fund sah nach dem Modell
besser aus als der Fundtag selbst. Beim Austernseitling steht dasselbe auf
der anderen Seite (0,401 „danach"). Das ist kein Auslöser-Signal, das ist
**die Steigung des Scores über die Saison**: Wo die Fruchtzeit einer Art
auf einem steilen Stück des Jahresgangs liegt, ist ein Tag 26 bis 45 Tage
daneben nicht mehr „dieselbe Saison".

Drei Dinge folgen daraus:

- **Die Haupt-AUC dieser vier Arten ist ein Mittel aus zwei sehr
  verschiedenen Zahlen.** Sie ist nicht falsch, aber sie ist spröder als
  die der Herbstarten: Schon eine Unwucht darin, wie viele Paare auf
  welcher Seite landen, verschiebt sie.
- **Die Spiegel-Kontrolle kann das bauartbedingt nicht sehen.** Sie
  vergleicht den Vergleichstag mit seiner Spiegelung; bei einer geraden
  Steigung liegen die beiden symmetrisch um den Fundtag, und der Effekt
  kürzt sich heraus. Genau deshalb steht sie bei Austernseitling trotz
  −0,439 sauber bei 0,510.
- **Für diese Arten gehört der Höchstabstand enger gefasst**, so wie
  Phase 0.3 es für Winterarten schon vorsieht. Welche Arten das betrifft,
  ist jetzt gemessen statt vermutet.

## 1.2 Frost-Vorlauf (beschreibend)

Anteil der Tage mit mindestens einem Frosttag (Tmin ≤ 0 °C) im Rueckblick, dazu Tage seit dem letzten Frost und Waermesumme seither. **Fundtag gegen Vergleichstag** — je Art dieselben Paare.

Wo kein Frost im 28-Tage-Fenster liegt, gibt es keine „Tage seit Frost“; solche Paare zaehlen bei dieser Kennzahl nicht mit, und die Spalte `n` sagt, wie viele uebrig bleiben. Eine Null dort waere die Behauptung „gerade erst gefroren“.

| Art | Frost in 7 d F/V | 14 d | 28 d | Tage seit Frost F/V | n | Waerme seit Frost F/V |
|---|---|---|---|---|--:|---|
| Steinpilz | 2% / 11% | 2% / 13% | 3% / 16% | 6.3 / 5.7 | 27 | 58 / 44 |
| Maronenröhrling | 3% / 14% | 4% / 17% | 4% / 20% | 6.3 / 5.5 | 38 | 53 / 38 |
| Birkenpilz | 1% / 9% | 1% / 12% | 1% / 14% | 5.1 / 6.1 | 9 | 50 / 51 |
| Fichtenreizker | 5% / 17% | 7% / 19% | 8% / 22% | 5.5 / 4.2 | 31 | 44 / 31 |
| Herbsttrompete | 0% / 14% | 2% / 18% | 2% / 18% | 11.7 / 4.1 | 3 | 112 / 26 |
| Pfifferling | 2% / 5% | 3% / 8% | 3% / 12% | 6.1 / 9.9 | 22 | 37 / 92 |
| Hallimasch | 9% / 22% | 12% / 29% | 14% / 31% | 5.9 / 4.9 | 129 | 45 / 33 |
| Stockschwämmchen | 7% / 20% | 10% / 26% | 12% / 30% | 6.7 / 5.5 | 68 | 55 / 42 |
| Austernseitling | 40% / 30% | 49% / 41% | 54% / 46% | 4.4 / 5.3 | 192 | 28 / 40 |
| Judasohr | 38% / 36% | 51% / 45% | 62% / 52% | 6.2 / 5.1 | 409 | 48 / 43 |
| Samtfußrübling | 67% / 44% | 84% / 57% | 89% / 62% | 4.2 / 4.6 | 285 | 25 / 34 |

### Was da steht

**Bei allen Herbst- und Holzarten haben Fundtage WENIGER Frost im
Rücken als Vergleichstage** (Steinpilz 2 % gegen 11 %). Das ist die
erwartete Richtung: Sie fruchten vor dem Frost.

**Beim Samtfußrübling dreht es sich um, und deutlich**: 67 % gegen 44 %
im Sieben-Tage-Rückblick, 89 % gegen 62 % über 28 Tage. Dazu weniger
Wärme seit dem letzten Frost (25 gegen 34). Das ist genau die Signatur,
die H3 unterstellt — Frost, dann eine kurze Wärmephase.

**Der Austernseitling zeigt dieselbe Richtung, schwächer** (40 % gegen
30 %, Wärme 28 gegen 40).

**Das Judasohr zeigt sie nicht.** Im Sieben-Tage-Rückblick 38 % gegen
36 % — praktisch kein Unterschied —, und bei der Wärmesumme steht es mit
48 gegen 43 sogar auf der anderen Seite als seine beiden
Klassengenossen.

Das ist der **dritte unabhängige Befund** in dieselbe Richtung: Im
Hold-out gewinnt das Judasohr als einziges nichts (Phase 0.4), sein
nachangepasstes Auslandsoptimum liegt bei 8,5 °C statt 3,5 °C, und jetzt
fehlt ihm auch die Frost-Signatur. Die Aufteilung des Fahrplans in H3
(Samtfußrübling, Austernseitling) und H3b (Judasohr) wird damit von drei
Seiten gestützt.

**Die Startbereiche für H3**, direkt aus der Tabelle abgelesen: Die
Trennung ist über 28 Tage am deutlichsten (89/62 gegen 67/44 über 7
Tage), der Rückblick L sollte also eher lang sein. Die Wärmesumme seit
dem Frost liegt bei Fundtagen um 25 K·d — die Sättigung F* gehört in
diese Größenordnung, nicht an den oberen Rand des Gitters.

## 1.3 Suchaufwand-Referenz — die Obergrenze des Aufwandssignals

Dieselbe Paarpruefung fuer **irgendeine Pilzmeldung am Ort** statt fuer eine Art. Wer meldet, war im Wald — unabhaengig davon, was er gefunden hat. Menschen gehen nach Regen in den Wald, ein Teil des Regensignals kann also Sammelverhalten sein.

**Was diese Zahl kann und was nicht:** Sie ist die Obergrenze des reinen Aufwandssignals. Artspezifisch belastbar ist nur, was eine Art darueber hinaus zeigt. Sie ist KEIN Abzugsposten — man darf sie nicht von der AUC einer Art subtrahieren, weil beide dieselbe Ursache teilen koennen.

| Fenster | AUC der Referenz | über Jahre | über Melder | Paare |
|---|--:|---|---|--:|
| herbst (13,0 °C) | **0.591** | [0.567, 0.614] | [0.549, 0.639] | 538 |
| sommer (17,5 °C) | 0.535 | [0.496, 0.588] | [0.492, 0.581] | 538 |
| kalt (−2,5 °C) | 0.533 | [0.494, 0.565] | [0.493, 0.572] | 538 |

538 Paare aus 12 Jahren und 199 Meldern. Beim Herbstfenster schließen
beide Bereiche die 0,50 aus, bei den anderen beiden nicht.

**Ein Vorbehalt, der dazugehört:** Die Spiegel-Kontrolle der Referenz
selbst steht bei **0,470** (487 Paare). Das liegt innerhalb der
Zwei-Fehler-Grenze (±0,045 bei dieser Paarzahl), aber außerhalb der
früheren festen ±0,03. Die Referenz ist damit nicht ganz so sauber wie
die Arten, an denen sie gemessen wird — was gegen eine Überinterpretation
der dritten Nachkommastelle spricht, nicht gegen die Größenordnung.

Richtungs-Split der Referenz (13 °C): vor 0.584, danach 0.598.

**Je Art gegen die Referenz** (nur das Fenster der eigenen Gruppe):

| Art | AUC der Art | AUC der Referenz | Ueberschuss |
|---|--:|--:|--:|
| Steinpilz | 0.737 | 0.591 | +0.146 |
| Maronenröhrling | 0.718 | 0.591 | +0.127 |
| Birkenpilz | 0.739 | 0.591 | +0.148 |
| Fichtenreizker | 0.756 | 0.591 | +0.165 |
| Herbsttrompete | 0.735 | 0.591 | +0.144 |
| Pfifferling | 0.643 | 0.535 | +0.107 |
| Hallimasch | 0.705 | 0.591 | +0.114 |
| Stockschwämmchen | 0.719 | 0.591 | +0.128 |
| Austernseitling | 0.637 | 0.533 | +0.104 |
| Judasohr | 0.585 | 0.533 | +0.052 |
| Samtfußrübling | 0.773 | 0.533 | +0.240 |

### Was da steht

**0,591.** So weit trägt das Ampel-Fenster für eine BELIEBIGE
Pilzmeldung. Das ist die wichtigste Zahl dieser Seite, und sie ist
unbequem.

Was sie NICHT heißt: dass 0,591 von der AUC einer Art abzuziehen wären.
„Irgendeine Pilzmeldung" ist nicht reiner Suchaufwand — es sind
überwiegend ANDERE PILZE, und die reagieren auf dasselbe Wetter. Die
Referenz ist damit zugleich eine Obergrenze für den Aufwand UND eine
Untergrenze für die allgemeine Pilz-Wetterreaktion. **Dieses Design kann
die beiden nicht trennen.**

Was sie sehr wohl heißt: Der artspezifische Überschuss der Herbstarten
liegt bei **+0,11 bis +0,17**, nicht bei den 0,74, die in der
Haupttabelle stehen. Wer die Ampel als „Arterkennung" liest, überschätzt
sie; als „heute ist Pilzwetter" gelesen, ist sie gut belegt — und genau
das ist der Satz, den die App ausgibt.

**Und das Judasohr liegt mit +0,052 am unteren Ende**, unter jeder
anderen gemessenen Art. Vierter Befund in dieselbe Richtung.

## 1.4 Melder-Abhaengigkeit

Traegt eine Handvoll Vielmelder die Zahl? Zwei Blickwinkel: die AUC **ohne** die zehn aktivsten Melder, und ein Bootstrap ueber **Melder** statt ueber Jahre.

Der Bootstrap ueber Melder ist der schaerfere: Paare derselben Person sind nicht unabhaengig, und wer ueber Paare zieht, bekommt einen zu engen Bereich. Zum Vergleich steht der Jahres-Bootstrap daneben — der ist der, mit dem bisher berichtet wurde.

| Art | Melder | Anteil der Top 10 | AUC gesamt | ohne Top 10 | Bootstrap ueber Melder | ueber Jahre |
|---|--:|--:|--:|--:|---|---|
| Steinpilz | 152 | 43% | 0.737 | 0.749 | [0.711, 0.765] | [0.694, 0.796] |
| Maronenröhrling | 164 | 43% | 0.718 | 0.729 | [0.685, 0.748] | [0.667, 0.762] |
| Birkenpilz | 140 | 30% | 0.739 | 0.747 | [0.698, 0.778] | [0.686, 0.785] |
| Fichtenreizker | 70 | 52% | 0.756 | 0.738 | [0.719, 0.796] | [0.708, 0.818] |
| Herbsttrompete | 45 | 52% | 0.735 | 0.729 | [0.676, 0.791] | [0.634, 0.846] |
| Pfifferling | 103 | 44% | 0.643 | 0.661 | [0.610, 0.676] | [0.599, 0.703] |
| Hallimasch | 192 | 46% | 0.705 | 0.697 | [0.670, 0.735] | [0.638, 0.768] |
| Stockschwämmchen | 123 | 52% | 0.719 | 0.699 | [0.669, 0.769] | [0.659, 0.765] |
| Austernseitling | 107 | 39% | 0.637 | 0.630 | [0.573, 0.698] | [0.555, 0.718] |
| Judasohr | 134 | 54% | 0.585 | 0.575 | [0.547, 0.619] | [0.555, 0.609] |
| Samtfußrübling | 76 | 60% | 0.773 | 0.822 | [0.737, 0.819] | [0.710, 0.848] |

### Was da steht

**Die Sorge trägt nicht.** Die zehn aktivsten Melder stellen 30 bis 60 %
der Paare — nimmt man sie heraus, bewegt sich die AUC um höchstens
0,049, und bei sieben von elf Arten nach OBEN.

**Der Bootstrap über Melder ist ENGER als der über Jahre**, und zwar bei
jeder einzelnen Art. Das war nicht zu erwarten und ist die eigentliche
Auskunft: Zwischen Jahren schwankt mehr als zwischen Meldern. Der
Jahres-Bootstrap, mit dem bisher berichtet wurde, ist damit der
vorsichtigere von beiden — **die veröffentlichten Vertrauensbereiche
waren nicht zu eng.**

## A5 — warum die Spiegel-Kontrolle wandert

Der Messbasis-Bericht schrieb die Wanderung dem **Instrument** zu,
gestützt auf drei Arten mit wechselnden Vorzeichen und einer
Rangkorrelation von −0,13. Der Auftrag nennt die naheliegende
Alternative: Die Spiegelung kürzt eine **gerade** Steigung heraus, aber
keine **Krümmung**. Beides ist nachgemessen — und die Antwort ist eine
dritte, einfachere.

Je Art über die drei per Konstruktion zeitgleich verteilten Punkte
(Vergleichstag, Fundtag, Spiegeltag) gerechnet, alles mit 13 °C wie im
Referenzlauf:

| Art | Spiegel | \|Abw\| | Krümmung | Steigung | Anteil „vor" |
|---|--:|--:|--:|--:|--:|
| Steinpilz | 0.500 | 0.000 | −0.531 | 0.0016 | 52,4 % |
| Maronenröhrling | 0.494 | 0.006 | −0.474 | 0.0026 | 52,7 % |
| Birkenpilz | 0.503 | 0.003 | −0.458 | 0.0015 | 53,3 % |
| Fichtenreizker | 0.491 | 0.009 | −0.488 | 0.0060 | 53,7 % |
| **Herbsttrompete** | **0.434** | **0.066** | −0.278 | **0.0383** | 50,9 % |
| **Pfifferling** | **0.462** | **0.038** | −0.197 | 0.0083 | 53,2 % |
| Hallimasch | 0.506 | 0.006 | −0.538 | 0.0031 | 52,9 % |
| Stockschwämmchen | 0.492 | 0.008 | −0.473 | −0.0073 | 54,2 % |
| Austernseitling | 0.510 | 0.010 | −0.179 | 0.0014 | **57,5 %** |

| Rangkorrelation gegen \|Abweichung von 0,5\| | |
|---|--:|
| \|Krümmung\| | **−0,68** |
| \|Steigung\| | +0,60 |
| \|Seitenunwucht\| | +0,12 |
| **\|Steigung × Seitenunwucht\|** | **+0,87** |

**Die Krümmungs-Erwartung trägt nicht** — das Vorzeichen ist falsch: Arten
mit der stärksten Krümmung haben die kleinste Abweichung. Die
Seitenunwucht allein trägt auch nichts (+0,12).

**Ihr Produkt trägt.** Und das ist mechanisch genau richtig: Eine gerade
Steigung kürzt sich nur heraus, wenn beide Seiten **gleich oft** gezogen
werden. `pick_control_day` wirft dafür eine Münze, und die lässt bei
n ≈ 2000 ein paar Prozent Unwucht stehen (hier 50,9 % bis 57,5 %). Wo
die Steigung flach ist, kostet das nichts; wo sie steil ist, schlägt es
durch. Die beiden markierten Arten sind genau die mit der steilsten
Steigung — die Herbsttrompete mit 0,0383 um das Sechsfache über der
nächsten.

**Ein Nebenbefund, der die Deutung des Pfifferlings ändert.** Seine
Spiegel-Kontrolle steht bei 0,462 mit dem 13-°C-Fenster, aber bei
**0,531 mit seinem eigenen** (17,5 °C). Die Ziehung ist also nicht
verzerrt — der 13-°C-Score verläuft über seine Saison bloß steil. Der
Satz aus Phase 0.4, seine Zahlen seien „nicht auswertbar", ist damit zu
scharf formuliert: Nicht auswertbar ist seine Auswertung MIT 13 °C.

**Was daraus folgt** (Vorschlag, nicht ausgeführt): Die Seiten exakt
auszubalancieren statt sie zu würfeln, kostet nichts und nimmt der
Spiegel-Kontrolle ihren größten Störer. Das ist eine Korrektur am
Messaufbau wie A1 bis A6 und gehört vor die Hypothesen — aber nach
Freigabe, weil sie jede Ziehung ändert.

## Grenzen

Gemessen wurde ausschliesslich an GBIF, in Deutschland, auf den Anpassjahren. Keine dieser Zahlen ist ein Beleg fuer irgendetwas — sie sagen, wo sich das Hinsehen lohnt.

Und keine ersetzt die Registrierung: Was aus ihnen folgt, wird als Hypothese aufgeschrieben, BEVOR sie an Pruefdaten kommt.
