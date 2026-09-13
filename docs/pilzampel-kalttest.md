# Kalttest: gibt es eine kalte KLASSE?

Stand: 2026-09-13 · Erzeugt von `tool/ampel_validate.py --cold` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wird das Temperaturoptimum je Art auf den Jahren bis **2018**, geprüft auf allen späteren — dasselbe Verfahren wie in `docs/pilzampel-artenfenster-messung.md`, dieselbe Stichprobengröße, derselbe Seed.

## Die Bedingung, die vor der Messung feststand

> Judasohr und Samtfußrübling landen **beide** bei einem Optimum unter 5 °C, und **beide** gewinnen gegenüber den ausgelieferten 13 °C mindestens **+0.05** AUC auf ihren Prüfjahren.

> **Beide oder keine.** Eine Klasse aus zwei Arten, von denen eine besteht, war vorab ausgeschlossen.

**Warum diese zwei Arten.** Sie waren an keiner Anpassung beteiligt — weder an der Glocke aus der Steinpilz-Literatur noch an den Fenstern der neun Arten. Unverbrauchte Daten sind der ganze Grund, warum hier etwas zu bestätigen ist.

## Gemessen

| Art | Paare Anpassung | Paare Prüfung | Optimum | bestes Band | AUC mit 13 °C | AUC angepasst | Differenz (95 %) | Bedingung |
|---|--:|--:|--:|---|--:|--:|---|---|
| Judasohr | 602 | 653 | 1.5 °C | 1.5 | 0.531 | 0.606 | +0.075 [+0.018, +0.146] | **erfüllt** |
| Samtfußrübling | 327 | 213 | -1.0 °C | -1.0 | 0.286 | 0.784 | +0.498 [+0.384, +0.574] | **erfüllt** |
| Austernseitling (Kontext) | 355 | 632 | -3.2 °C | -3.5 bis -3.0 | 0.481 | 0.655 | +0.174 [+0.108, +0.248] | tritt nicht an |

Die Kontextzeile ist das bereits gemessene Mitglied, aus dem Cache nachgerechnet. Sie steht da, weil eine Klasse ihre Mitglieder zusammen zeigen muss — und **nicht als Prüfling**: Der Austernseitling hat das kalte Fenster überhaupt erst aufgeworfen, an ihm ist nichts zu bestätigen.

## Der Ausgang

**Bestanden — beide Arten, beide Hälften.** Damit stehen 3 Arten mit kaltem Fenster, unabhängig voneinander gemessen. „Kalt“ ist damit eine Klasse und nicht die Eigenschaft einer Art.

Was daraus folgt, und in dieser Reihenfolge:

1. **Das Fenster der Klasse ist abgeleitet, nicht gewählt:** der Median der Optima ihrer Mitglieder, also **-1.0 °C** aus -3.2, -1.0, 1.5 °C.
2. **Die Schwellen müssen GEMESSEN werden**, als Quantil der Vergleichstage dieses Fensters (`--thresholds`, `docs/pilzampel-schwellen.md`). Ein eigenes Fenster ohne eigene Schwellen macht die Ampel dunkel, nicht besser — beim Austernseitling fiel „günstig“ mit den ausgelieferten Schwellen von 21,7 auf 1,1 % der Fundtage.
3. **Erst dann darf sie in die App**, samt ihren Mitgliedern in `ampelSpeciesClass`.
4. **Und die Häufigkeit ist neu zu messen:** Jede weitere Klasse lässt die Fläche öfter „günstig“ sagen (19,9 % → 30,2 % beim Sprung auf zwei Klassen). Wie oft sie das sagen soll, ist eine Produktentscheidung und keine Messung.

**Eine Zahl braucht hier ihre Deutung:** Samtfußrübling startet bei 0.286 — also UNTER 0,5. Mit den ausgelieferten 13 °C zeigt das Modell für diese Art in die falsche Richtung: Fundtage stehen schlechter da als Vergleichstage derselben Saison. Der größte Teil der Differenz ist deshalb die Korrektur dieses Vorzeichens und nicht die Feinheit des neuen Fensters. Für die Frage „gibt es eine kalte Klasse“ ist genau das die Antwort — für die Frage „wie gut trifft die Ampel“ nicht.

## Grenzen

Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199, und wer sie einrechnet, kann mit ihnen nicht mehr prüfen.

Auch ein bestätigtes Fenster sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
