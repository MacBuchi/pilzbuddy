# Artenfenster: der geografische Hold-out

Stand: 2026-09-12 · Erzeugt von `tool/ampel_validate.py --holdout` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wurde in **Deutschland** (Jahre bis 2018), geprüft in **AT und CH** — dort sind ALLE Jahre Prüfjahre, denn an der Anpassung war keiner von ihnen beteiligt. Das beantwortet, was eine weitere Zeitscheibe nicht mehr kann: ob das Fenster der ART gehört oder der deutschen Stichprobe.

## Die Schwelle, die vor der Messung feststand

> Die gepaarte AUC mit dem angepassten Optimum liegt im Hold-out mindestens **+0.05** über der mit 13 °C.

## Pfifferling

Optimum aus Deutschland: **19.2 °C** (1336 Paare). Im Hold-out 1917 Paare aus 20 Jahren.

| | AUC |
|---|--:|
| mit 13 °C | 0.549 |
| mit 19.2 °C | 0.643 |
| Differenz | **+0.094** [+0.040, +0.152] |

**Ergebnis: NICHT AUSWERTBAR — die Placebo-Kontrolle ist verzerrt** (Schwelle +0.05).

Placebo-Kontrolle im Hold-out: 0.550 bei 1861 Paaren (Toleranz ±0.03) — erwartbar abweichend, siehe unten.
**Abstandsgleiche Kontrolle: 0.532** bei 1915 Paaren — der Vergleichstag gegen seine Spiegelung am Fundtag, beide exakt gleich weit weg — **verzerrt.** Zwei fundfreie Tage, nach derselben Vorschrift gezogen, dürfen sich nicht unterscheiden. Tun sie es doch, misst der Aufbau etwas anderes als das Wetter am Fundtag, und die Zahlen darüber sind keine Aussage über das Modell.

