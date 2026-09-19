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

## Was auf einer Achse KEINE Achse verbraucht

**Beschreibende Statistiken, die von keiner Schwelle abhängen** — seit
dem 2026-09-19 (Betreiberentscheidung, Auftrag 3 A).

Der Grund ist, dass **Schwelle und gepaarte AUC disjunkte Statistiken**
sind. Die AUC ist rangbasiert: Sie zählt, wie oft ein Fundtag seinen
Kontrolltag schlägt, und kennt keine Schwelle. Eine aus P1 gezogene
Schwelle kann deshalb keinen bisherigen und keinen künftigen AUC-Test
berühren — es gibt dort keine Latte, kein Band und nichts zu bestehen.
Beschrieben wird eine Verteilung, nicht ausgewählt.

Und für eine Schwelle ist P1 sogar die richtige Scheibe: Die App steht
heute, nicht 2012. Die Zeitscheibe allein macht beim Pfifferling über
ein Drittel des gemessenen Sprungs aus
(`pilzampel-schwellen-designb.md`).

### Die Gegenregel, und sie ist scharf

> **Schwellenabhängige Gütemaße sind auf P1 gesperrt** — Trefferquote,
> POD, FAR, TSS und der Hebel. Wer so etwas braucht, rechnet es auf
> AT+CH.

Sobald ein Maß eine Schwelle BENUTZT, um Fundtage zu bewerten, ist es
kein Verteilungsbefund mehr, sondern eine Güte — und dann entschiede
die ausgelieferte Zahl mit, wie gut die Ampel aussieht. Dort wäre die
Kontamination echt.

Der Riegel steht im Code, nicht nur hier: `verbiete_schwellenmass` in
`tool/ampel_diagnose.py` bricht den Lauf ab, und auf P1 werden die
Fundtage gar nicht erst bewertet.

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
| 11 | 2026-09-19 | H6: Sommer-Optimum 14,0 °C statt 17,5 °C | **AT + CH** | **nicht bestanden** — Δ +0,014, p = 0,29, und 9 von 20 Fundjahren bewegen sich in die Gegenrichtung | `pilzampel-h6-ergebnis.md` |

### Stand je Achse

| Achse | Läufe | davon bestanden |
|---|--:|--:|
| DE ≥ 2019 | 3 (#1, #3, #9) | 1½ |
| **AT + CH** | **6** (#2, #4, #5, #8, #10, #11) | 1 |
| fremde Arten | 1 (#7) | 0 — der Plan war fehlerhaft |

---

## Was diese Liste sagt

**AT + CH ist die meistbenutzte und die knappste Achse.** Sechs Läufe,
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

## Die Regel, die seit dem 2026-09-19 gilt

> **Kein Lauf auf einer Achse ohne vorherigen Auflösungs- und
> Plausibilitätscheck auf den Anpassjahren DE ≤ 2018.**

Betreiberauflage vom 2026-09-19. Sie hätte #7 verhindert: Dort waren die
Gruppen nach dem **Saisongipfel** gebildet, während die Hypothese über
**Temperatur** ging — und die mittlere Fundtag-Temperatur je Art hing an
keiner AUC, war also vorher auf den Anpassjahren ablesbar. Zwei der drei
„Kontrastarten" fruchten bei 10,6 und 16,7 °C, beide mitten in der
Glocke. Der Plan konnte die Frage nicht beantworten, und das war vor der
Messung zu sehen (`pilzampel-kontrastgruppe-fehler.md`).

Der Check beantwortet zwei Fragen, beide auf Anpassjahren:

- **Auflösung:** Kann der Aufbau einen Effekt dieser Größe überhaupt
  sehen? Paarzahl, Standardfehler über Fundjahre, nachweisbare
  Effektgröße — wie in N3 gerechnet.
- **Plausibilität:** Misst der Plan die Größe, um die es geht? Stehen
  die Gruppen, Fenster und Stellvertreter zu der Hypothese, die geprüft
  werden soll?

Er ist **kein Vortest**: Ein gutes Ergebnis auf den Anpassjahren belegt
nichts und darf die Latte der eigentlichen Prüfung nicht verschieben. Er
verhindert nur, dass eine Achse für eine Frage ausgegeben wird, die so
nicht beantwortbar ist.

**Erster Lauf unter dieser Regel:** `docs/pilzampel-h5-vorpruefung.md`
— und er hat sofort getragen. Die Zerlegung „Regen allein schlägt
Temperatur allein", auf P1 bei 11 von 11 Arten sichtbar, kehrt auf den
Anpassjahren bei nur 1 von 6 wieder. **H5 wurde deshalb nicht
registriert, und AT+CH ist nicht angefasst worden**
(`docs/pilzampel-h5-vorpruefung-ergebnis.md`).

Ohne die Regel wäre die sechste Frage an AT+CH gegangen — für eine
Beobachtung, die eine Zeitscheibe weiter nicht mehr da ist.

### Vorprüfungen (kosten keine Achse)

| Datum | Frage | Ausgang | Beleg |
|---|---|---|---|
| 2026-09-19 | Trägt die Glocke etwas bei? Zerlegung auf P3 | **H5 nicht registriert** — 1 von 6 statt 5 von 6 | `pilzampel-h5-vorpruefung-ergebnis.md` |
| 2026-09-19 | Wo lägen die Schwellen an Design-B-Kontrolltagen? (Auftrag 3 A) | Vorlage, nichts übernommen — die ausgelieferten Schwellen greifen an B-Tagen 1,7-mal so oft wie vorgesehen | `pilzampel-schwellen-designb.md` |
| 2026-09-19 | Alterung: dieselbe Zerlegung auf geteilten Anpassjahren | die Glocke altert nicht, der Einbruch liegt in den Prüfjahren | `pilzampel-alterung.md` |
| 2026-09-19 | H6: hält das Sommer-Optimum still? (Auftrag 3 B) | **H6 nicht registriert** — V1 gefallen (Gitter 15,00 gegen Logit 13,16 °C); das harte Abbruchkriterium V2 hat gehalten | `pilzampel-h6-vorpruefung-ergebnis.md` |

### Diagnosen auf P1 (kosten ebenfalls keine Achse)

Nur, was von keiner Schwelle abhängt — die Begründung steht oben unter
„Was auf einer Achse KEINE Achse verbraucht".

| Datum | Frage | Ausgang | Beleg |
|---|---|---|---|
| 2026-09-19 | Wo liegen die Schwellen an Design-B-Kontrolltagen der Prüfjahre? | **übernommen in 1.144.0** — 0,389/0,742 und 0,385/0,729 | `pilzampel-schwellen-designb-p1.md` |

## Folge für die nächste Hypothese

Wer eine neue Bedingung registriert, trägt **vorher** ein, welche Achse
sie verbraucht — und begründet, warum die Idee nicht aus derselben Achse
stammt, auf der sie geprüft werden soll.

**Offen und hier festgehalten:** Die Zerlegung „Temperatur allein gegen
Regen allein" aus `docs/pilzampel-h1-ergebnis.md` wurde auf **P1, also
DE ≥ 2019** gerechnet. Jede Hypothese, die aus dieser Beobachtung folgt,
ist damit auf dieser Achse **entstanden** und kann dort nicht mehr
unbefangen geprüft werden.
