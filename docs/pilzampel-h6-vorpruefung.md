# Vorprüfung zu H6: hält ein Optimum aus Design B überhaupt still?

Stand: 2026-09-19 · Auftrag: `docs/pilzampel-auftrag-3.md`, Abschnitt B ·
**vor dem Lauf geschrieben, danach nicht mehr angefasst**

Diese Seite entscheidet **nicht**, ob die 17,5 °C falsch sind. Sie
entscheidet, ob H6 überhaupt registriert wird — und sie legt vorher
fest, woran.

---

## Der Anlass

Die ausgelieferten 17,5 °C des Pfifferlings stammen aus **Design A**, wo
bei einem Sommerfrüchter der Vergleichstag 26 bis 45 Tage daneben liegt
— also im Frühjahr oder Herbst, und beides ist kühler als Juli. Der
Fundtag sieht dort zwangsläufig warm aus, und ein angepasstes Optimum
wandert nach oben, ohne dass etwas über das Wetter gesagt wäre
(`docs/pilzampel-formel.md`, Herabstufung vom 2026-09-19).

Drei Zahlen stehen dagegen:

- Das bedingte Logit in Design B sagt **13,16 ± 0,94 °C**
  (cluster-robust) — rund viereinhalb Standardfehler unter der
  Konstante (`docs/pilzampel-logit.md`).
- Auf P3 trennt die Sommerglocke mit **0,512**, praktisch gar nicht;
  der Regen derselben Art mit 0,632
  (`docs/pilzampel-h5-vorpruefung-ergebnis.md`).
- Der Pfifferling liegt trotzdem **+0,054** über seiner artgematchten
  Referenz (`docs/pilzampel-kontrolldesign.md`). Es ist also etwas da —
  nur vielleicht nicht in der Glocke.

## Warum eine Vorprüfung, und warum auf P3

Die Prüfachse wäre **AT + CH**, und die ist die knappste: fünf Läufe,
einer bestanden (`docs/pilzampel-pruefachsen.md`). Seit dem 2026-09-19
gilt: kein Lauf auf einer Achse ohne vorherigen Auflösungs- und
Plausibilitätscheck auf P3.

Das Risiko hat einen Namen. **Phase 0.4 hat gemessen, dass angepasste
Optima wandern** — je nach Zeitscheibe, je nach Ziehung. Ein Optimum,
das zwischen zwei Hälften der Anpassjahre um mehrere Grad springt, ist
keine Eigenschaft der Art, sondern eine der Stichprobe. Genau das ist
hier zu prüfen, **bevor** eine Achse dafür ausgegeben wird.

## Was gerechnet wird

Auf P3 (DE ≤ 2018), Design B, Messbasis `pinned`, Entdoppeln an, Seed 42
— dieselbe Ziehung wie überall in dieser Arbeit. Gegenstand ist **eine
Art**, der Pfifferling; die Klasse `sommer` hat nur dieses Mitglied.

### V1 — stimmen zwei Wege überein?

| Weg | wie |
|---|---|
| **Logit** | bedingtes Logit auf den B-Strata, Merkmale `[log F, T̄₂₀, T̄₂₀²]`, Optimum = `−b_T / (2·b_T²)`, cluster-robuster Fehler über Fundjahre, Delta-Methode |
| **Gitter** | das Optimum, das das **B-Maß** maximiert; Gitter 5,0 bis 25,0 °C in 0,25-K-Schritten, Fehler aus dem Jahres-Bootstrap |

> **Bedingung V1:** `|Optimum_Logit − Optimum_Gitter| ≤ 1,0 K`.

Warum 1,0 K und keine Signifikanzschranke: Beide Schätzer laufen auf
**denselben Daten**, ihre Fehler sind also stark korreliert, und die
übliche Formel `1,96·√(SE₁²+SE₂²)` wäre hier viel zu großzügig — sie
würde Übereinstimmung fast erzwingen. Die Streitfrage ist gut 4 K groß
(17,5 gegen 13,2); ein Methodenunterschied von mehr als 1 K wäre ein
Viertel davon, und dann stritten die beiden Wege über einen relevanten
Teil der Antwort. Die statistische Fassung wird trotzdem berichtet.

### V2 — das harte Abbruchkriterium

Dieselben beiden Schätzer auf den **geteilten Anpassjahren**: 2006–2012
gegen 2013–2018.

> **Bedingung V2:** `|Optimum(2006–12) − Optimum(2013–18)| ≤ SE(Optimum
> auf ganz P3)`.
>
> Verletzt ⇒ **H6 wird nicht registriert.**

Maßgeblich ist das **Gitter-Optimum**, denn das ist der Wert, der
registriert würde; die Logit-Fassung läuft daneben und wird berichtet.

**Das ist die strenge Lesart, und sie ist Absicht.** Die Differenz
zweier Halbjahres-Schätzer hat rechnerisch einen Fehler von etwa
`√2·SE_Hälfte ≈ 2·SE_ganz`; gegen den gemessen wäre fast jede Drift
unauffällig. Verglichen wird stattdessen gegen die Genauigkeit, die wir
für die **ausgelieferte** Zahl behaupten würden. Wandert das Optimum um
mehr als das, ist die Behauptung nicht haltbar — egal, ob ein Test sie
für signifikant hält. Die großzügige Fassung steht im Bericht daneben.

**Zu dünn ist kein Bestehen.** Hat eine Hälfte weniger als 150 Funde,
ist V2 nicht auswertbar, und H6 wird **nicht** registriert. Ein
Kriterium, das man nicht prüfen kann, ist keines, das man bestanden hat.

### V3 — wieviel kann überhaupt herauskommen?

Der **Diskordanzanteil** zwischen altem und neuem Score: der Anteil der
B-Vergleiche (Fundtag gegen einen Kontrolltag), bei denen die beiden
Optima das Paar **verschieden** ordnen.

Ein Vergleich, den beide gleich ordnen, kann zum Unterschied nichts
beitragen; einer, der kippt, höchstens 1. Also:

> `|ΔB| ≤ Diskordanzanteil` — die Obergrenze der Effektgröße.

Berichtet wird dazu das tatsächliche ΔB auf P3. Das ist eine Diagnose
und kein Beleg: P3 sind die Anpassjahre, und das neue Optimum stammt
von dort.

### V4 — kann der Aufbau das sehen?

Jahres-Bootstrap der **Differenz je Zug**, nicht zweier Bänder: Pro Zug
werden Fundjahre mit Zurücklegen gezogen, und auf **denselben** Funden
werden beide Optima bewertet. Zwei getrennte Bänder überschätzten die
Streuung, weil sie die Paarung wegwerfen.

Daraus der Standardfehler und die **nachweisbare Effektgröße**
`MDE = (z₀,₉₇₅ + z₀,₈₀)·SE = 2,802·SE`.

> **Bedingung V4:** `MDE < Diskordanzanteil aus V3`.

Sonst kann der Aufbau den größtmöglichen Effekt nicht von null
unterscheiden, und ein „nicht bestanden" auf der Achse hieße nur, dass
zu wenig Material da war.

## Die Entscheidung, vorab festgelegt

| Ausgang | Folge |
|---|---|
| **V1, V2 und V4 erfüllt** | H6 wird registriert. Geprüft wird auf **AT + CH**; der Wert wird auf P3 festgelegt und eingefroren. |
| **V2 verletzt** | **H6 wird nicht registriert.** Das Optimum ist eine Eigenschaft der Stichprobe, nicht der Art — genau der Befund aus Phase 0.4, und er ist ein Ergebnis, kein Anlass für einen zweiten Anlauf. |
| **V1 verletzt** | H6 wird nicht registriert. Zwei Wege, die auf denselben Daten über 1 K streiten, liefern keinen Wert zum Einfrieren. |
| **V4 verletzt** | H6 wird nicht registriert. Die Achse würde für eine Frage ausgegeben, die sie nicht beantworten kann. |

**Kein Zwischenergebnis wird nachverhandelt.** Fällt eine Bedingung
knapp, ist sie gefallen. Die Zahlen kommen in den Bericht, die Schwellen
bleiben, wie sie hier stehen.

Zur Einordnung, ebenfalls vorab: Der Betreiber hat am 2026-09-19
festgehalten, dass die Ampel experimentell ist und ein knapp verfehltes
Kriterium kein Grund sein muss, eine brauchbare Idee wegzuwerfen. Das
ändert an dieser Seite nichts — **die Zahl wird hingeschrieben, nicht
die Latte verschoben.** Wenn etwas knapp fällt, steht der Abstand im
Bericht, und die Entscheidung darüber ist eine Betreiberentscheidung
und keine, die ich still treffe.

## Was diese Seite nicht kann

- **Sie prüft nichts.** P3 sind die Anpassjahre; jede Zahl von dort ist
  eine Diagnose. Selbst ein glänzendes Ergebnis belegt H6 nicht — es
  erlaubt nur, H6 zu registrieren.
- **Sie sagt nichts über σ.** Das Logit bewegt Mitte und Breite
  zusammen; H1 hat die Breite allein angegriffen und verloren
  (`docs/pilzampel-h1-ergebnis.md`). H6 fasst σ = 5,0 nicht an, und
  damit bleibt offen, ob ein verschobenes Optimum bei fester Breite
  überhaupt die richtige Bewegung ist.
- **Sie sagt nichts über die Herbstklasse.** Die bleibt unangetastet
  (Auftrag 3 C).

## Der Lauf

```
python3 tool/ampel_diagnose.py --h6 \
    --dataset pinned --dedupe \
    --api http://127.0.0.1:8080/v1/archive \
    --cache ~/pilzbuddy-ampel2000/ampel_cache_pinned \
    --seed 42 \
    --out docs/pilzampel-h6-vorpruefung-ergebnis.md
```
