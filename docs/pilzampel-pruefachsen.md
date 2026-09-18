# Prüfachsen — die Strichliste

Stand: 2026-09-19 · Angelegt auf Auflage des Betreibers (2026-09-19):
„Ab hier braucht es eine Strichliste im Repo, sonst verlieren die Bänder
ihre Bedeutung, ohne dass es jemand merkt."

**Wozu.** Jede Prüfung an denselben Daten kostet etwas. Wer dieselbe
Achse mehrfach befragt, findet irgendwann etwas — und das
Vertrauensintervall daneben sagt davon nichts. Diese Seite ist das
Gedächtnis dafür.

**Regel:** Jeder Lauf, der eine Bedingung gegen Daten prüft, kommt hier
hinein — **bevor** sein Ergebnis irgendwo zitiert wird. Diagnosen und
Anpassungen auf den Anpassjahren gehören nicht hierher; sie verbrauchen
keine Achse.

---

## Die Achsen

| Achse | was sie ist | warum sie zählt |
|---|---|---|
| **DE ≥ 2019** | Deutschland, Prüfjahre | Die Anpassjahre DE ≤ 2018 sind für Optima und Schwellen benutzt worden. |
| **AT + CH** | Österreich und Schweiz, alle Jahre | An keiner Anpassung beteiligt — der teuerste und knappste Raum. |
| **fremde Arten** | Arten, für die nie etwas angepasst wurde | Eine eigene Achse: Das 13-°C-Fenster ist Literatur, also ist jede neue Art eine Prüfung. |

**Die Anpassjahre DE ≤ 2018 sind keine Achse.** Dort wird gefittet und
diagnostiziert; ein Ergebnis von dort ist nie ein Beleg.

---

## Strichliste

| # | Datum | Was geprüft wurde | Achse | Ausgang | Beleg |
|--:|---|---|---|---|---|
| 1 | 2026-09-12 | Artenfenster je Art (Optimum je Art gegen 13 °C) | DE ≥ 2019 | teils bestanden — 3 von 6 Arten | `pilzampel-artenfenster-messung.md` |
| 2 | 2026-09-12 | Pfifferling-Fenster 17,5 °C, geografisch | **AT + CH** | bestanden (+0,104) | `pilzampel-artenfenster-holdout.md` |
| 3 | 2026-09-13 | Kalttest: gibt es eine kalte Klasse? | DE ≥ 2019 | bestanden | `pilzampel-kalttest.md` |
| 4 | 2026-09-13 | Kaltklasse, geografisch | **AT + CH** | **nicht bestanden** (Judasohr −0,066) | `pilzampel-kaltklasse-holdout.md` |
| 5 | 2026-09-13 | Klasse `herbst_holz`, geografisch | **AT + CH** | **nicht bestanden** (Stockschwämmchen −0,036) | `pilzampel-herbstholz-holdout.md` |
| 6 | 2026-09-13 | Schwellen: welchem Quantil entsprechen 0,2 und 0,5? | Anpassjahre (Prüfjahr-Spalte als Diagnose) | Vorhersage nicht bestätigt | `pilzampel-schwellen-messung.md` |
| 7 | 2026-09-17 | Trägt das 13-°C-Fenster an Arten, für die es nie angepasst wurde? | **fremde Arten**, DE | Ausgang `generisch` — **Plan war fehlerhaft**, siehe `pilzampel-kontrastgruppe-fehler.md` | `pilzampel-herbstklasse-messung.md` |
| 8 | 2026-09-18 | Kaltklasse erneut, auf der gepinnten Messbasis | **AT + CH** (Wiederholung von #4) | nicht bestanden, Begründung von #4 trägt nicht mehr | `pilzampel-messbasis.md` |
| 9 | 2026-09-18 | H1: σ = 3,25 K gegen 5,0 K | DE ≥ 2019 (P1) | **nicht bestanden** | `pilzampel-h1-ergebnis.md` |
| 10 | 2026-09-18 | H1, Reisetest derselben Frage | **AT + CH** (P2) | Pfifferling kippt nach unten | `pilzampel-h1-ergebnis.md` |

### Stand je Achse

| Achse | Läufe | davon bestanden |
|---|--:|--:|
| DE ≥ 2019 | 3 (#1, #3, #9) | 1½ |
| **AT + CH** | **5** (#2, #4, #5, #8, #10) | 1 |
| fremde Arten | 1 (#7) | 0 — der Plan war fehlerhaft |

---

## Was diese Liste sagt

**AT + CH ist die meistbenutzte und die knappste Achse.** Fünf Läufe,
davon #8 eine Wiederholung von #4 auf neuer Messbasis. Die
Meldungszahlen dort sind klein (Austernseitling 288, Samtfußrübling 367),
und jede weitere Frage macht die verbleibenden enger — nicht rechnerisch,
sondern in dem Sinn, dass ein dort gefundener Effekt immer weniger
überrascht.

**Zweimal dieselbe Frage ist nicht zweimal dieselbe Information.** #4 und
#8 sind dieselbe Hypothese auf zwei Messbasen. Der zweite Lauf hat den
Ausgang bestätigt und die **Begründung** widerlegt — das ist ein Gewinn,
aber er hat eine Achse gekostet.

**Eine fehlerhafte Prüfung kostet trotzdem.** #7 hat seinen Ausgang
geliefert und war unbrauchbar, weil die Gruppen nach dem Kalender
gebildet waren statt nach der Temperatur. Die Arten sind damit gesehen;
eine Wiederholung an denselben Arten wäre keine frische Prüfung mehr.

---

## Folge für die nächste Hypothese

Wer eine neue Bedingung registriert, trägt **vorher** ein, welche Achse
sie verbraucht — und begründet, warum die Idee nicht aus derselben Achse
stammt, auf der sie geprüft werden soll.

**Offen und hier festgehalten:** Die Zerlegung „Temperatur allein gegen
Regen allein" aus `docs/pilzampel-h1-ergebnis.md` wurde auf **P1, also
DE ≥ 2019** gerechnet. Jede Hypothese, die aus dieser Beobachtung folgt,
ist damit auf dieser Achse **entstanden** und kann dort nicht mehr
unbefangen geprüft werden.
