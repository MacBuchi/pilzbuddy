# Artenfenster: der geografische Hold-out

Stand: 2026-09-12 · Erzeugt von `tool/ampel_validate.py --holdout` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wurde in **Deutschland** (Jahre bis 2018), geprüft in **AT und CH** — dort sind ALLE Jahre Prüfjahre, denn an der Anpassung war keiner von ihnen beteiligt. Das beantwortet, was eine weitere Zeitscheibe nicht mehr kann: ob das Fenster der ART gehört oder der deutschen Stichprobe.

## Die Schwelle, die vor der Messung feststand

> Die gepaarte AUC mit dem angepassten Optimum liegt im Hold-out mindestens **+0.05** über der mit 13 °C.

## Pfifferling

Optimum aus Deutschland: **17.5 °C** (1332 Paare). Im Hold-out 1915 Paare aus 20 Jahren.

| | AUC |
|---|--:|
| mit 13 °C | 0.584 |
| mit 17.5 °C | 0.689 |
| Differenz | **+0.104** [+0.055, +0.150] |

**Ergebnis: bestätigt** (Schwelle +0.05).

Placebo-Kontrolle im Hold-out: 0.542 bei 1817 Paaren (Toleranz ±0.03) — erwartbar abweichend, siehe unten.
**Abstandsgleiche Kontrolle: 0.510** bei 1911 Paaren — der Vergleichstag gegen seine Spiegelung am Fundtag, beide exakt gleich weit weg — unauffällig. Daran hängt das Urteil oben.

