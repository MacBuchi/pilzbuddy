# Die Formel der Ampel — woher jede Zahl kommt

Stand: 2026-09-19 · Verlangt von `docs/pilzampel-fahrplan.md` („Herkunfts­tabelle:
gesetzt → gemessen") und `docs/pilzampel-auftrag-2.md`, Abschnitt 5

Diese Seite beantwortet genau eine Frage: **Welche Konstante der Ampel ist
gemessen, welche ist gesetzt — und wenn gemessen, in welchem Design?**

Sie ändert keine Konstante. Wo hier etwas herabgestuft wird, betrifft das
die Herkunftsangabe, nicht den Wert.

---

## Die Formel

    Score = Regenfaktor(26 d) · exp( −((T̄₂₀ − Optimum) / σ)² )

Die Saisonkurve ist **kein Faktor**, sondern ein Tor an den Spots
(`lib/features/ampel/ampel_scan.dart`). Sie steht deshalb nicht in dieser
Tabelle.

## Die Herkunftstabelle

Drei Stufen, und die mittlere ist neu:

| Stufe | heißt |
|---|---|
| **gesetzt** | nie gemessen — eine Annahme, die plausibel aussieht |
| **gemessen (Design A)** | gemessen, aber in einem Design, das die Jahreszeit mitmisst |
| **gemessen (Design B)** | gemessen gegen dasselbe Datum anderer Jahre — der Kalender ist heraus |

| Konstante | Wert | Herkunft | Beleg |
|---|--:|---|---|
| `ampelRainWindow` | 26 d | **gesetzt** — aus der Sammlerregel „100 mm in 30 Tagen", heruntergerechnet | `docs/pilzampel-konzept.md` |
| `ampelRainSaturationMm` | 87 mm | **gesetzt** — dieselbe Regel | `docs/pilzampel-konzept.md` |
| `ampelTempWindow` | 20 d | **extern gemessen** — Bielefelder Steinpilz-Reihe, zehn Jahre, ein Standort, eine Art | Brejon Lamartiniere & Hoffman 2025 |
| `ampelOptimumC` (herbst) | 13,0 °C | **extern gemessen** — dieselbe Reihe. In GBIF nie angepasst, aber an fremden Arten geprüft | `docs/pilzampel-herbstklasse-messung.md` |
| `ampelTempSigma` | 5,0 K | **gesetzt** — das Papier nennt einen Gipfel, keine Streuung. Am 2026-09-18 erstmals angegriffen und **nicht geschlagen** | `docs/pilzampel-h1-ergebnis.md` |
| `ampelSommerClass.optimumC` | 17,5 °C | **gemessen (Design A)** — angepasst auf DE ≤ 2018, Hold-out AT+CH bestanden. **Siehe Herabstufung unten.** | `docs/pilzampel-artenfenster-messung.md`, `…-holdout.md` |
| `ampelHerbstClass` Schwellen | 0,187 / 0,512 | **gemessen (Design A)** — 50-%- und 80-%-Quantil der Score-Verteilung an Vergleichstagen, Anpassjahre | `docs/pilzampel-schwellen-messung.md` |
| `ampelSommerClass` Schwellen | 0,287 / 0,677 | **gemessen (Design A)** — dito | `docs/pilzampel-schwellen-messung.md` |
| Höhenkorrektur | 0,65 K/100 m | **extern gesetzt** — trockenadiabatischer Standardwert, nicht an unseren Daten geprüft | `lib/features/ampel/ampel_providers.dart` |
| Messbasis | `era5_seamless` | **gemessen** — der Instrumentwechsel und seine Folgen sind beziffert | `docs/pilzampel-messbasis.md` |

---

## Herabstufung vom 2026-09-19: die 17,5 °C des Pfifferlings

**Bisher stand diese Zahl als „gemessen" da. Das war zu stark.**

Sie wurde mit `tool/ampel_validate.py --fit` auf DE ≤ 2018 angepasst und
in AT+CH geprüft — beides in **Design A**, wo der Vergleichstag 26 bis 45
Tage neben dem Fund im selben Jahr liegt. Bei einem Sommerfrüchter heißt
das Frühjahr oder Herbst, und beides ist kühler als Juli. Der Fundtag
sieht dort zwangsläufig warm aus, und ein angepasstes Optimum wandert
nach oben, ohne dass etwas über das Wetter gesagt wäre.

Dass genau das passiert ist, legt das bedingte Logit in Design B nahe:
Dort steht der Pfifferling bei **13,16 ± 0,94 °C** (cluster-robust), rund
viereinhalb Standardfehler unter der ausgelieferten Konstante und näher
an der Herbstklasse als an seinem eigenen Fenster
(`docs/pilzampel-logit.md`). Er ist die einzige Art, deren Abstand zur
ausgelieferten Zahl den robusten Fehler übersteht.

**Was sich dadurch NICHT ändert:**

- **Der Wert bleibt bei 17,5 °C.** Eine Konstante nach dem Blick auf eine
  Nebenrechnung zu verschieben, wäre genau der Griff, gegen den der ganze
  Aufbau antritt.
- **Der Hold-out-Erfolg bleibt als Messung stehen.** Er wurde in Design A
  erzielt und gilt dort; die Zahlen in `…-holdout.md` werden nicht
  angefasst.
- **Der Pfifferling bleibt die bestbelegte Art.** In Design B steht er
  auf „belegt" und liegt +0,054 über seiner artgematchten Referenz
  (`docs/pilzampel-kontrolldesign.md`).

**Was sich ändert:** Wer künftig liest „das Fenster des Pfifferlings ist
gemessen", liest jetzt dazu, in welchem Design. Wer es anfassen will,
braucht eine eigene Registrierung — und die müsste in Design B laufen.

Dieselbe Herabstufung gilt sinngemäß für **jede** Zeile, die oben
„gemessen (Design A)" trägt, auch für die vier Schwellen. Phase 1.5 hat
gezeigt, dass Design A bei den Herbstarten rund 0,09 AUC Kalender enthält
(`docs/pilzampel-kontrolldesign.md`); eine auf Design A geeichte Schwelle
trägt denselben Anteil.

---

## Was daraus folgt, und was nicht

**Die Ampel ruht auf mehr Gesetztem als auf Gemessenem.** Von den vier
Größen der Kernformel sind zwei gesetzt (Regenfenster, Sättigung), eine
extern gemessen an einem Standort (Optimum 13 °C) und eine gesetzt und
inzwischen erfolglos angegriffen (σ = 5 K). Das ist kein Vorwurf —
so fängt jedes Modell an. Es ist der Grund, warum das Feature hinter
einem Schalter steht und „experimentell" heißt.

**Und eine erfolglos angegriffene Zahl ist nicht bestätigt.** σ = 5 K hat
H1 überstanden; das heißt, dass 3,25 K bei festgehaltenem Optimum nicht
besser trennt. Es heißt nicht, dass 5 K richtig ist.
