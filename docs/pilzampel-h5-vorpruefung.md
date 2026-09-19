# Vorprüfung zu H5: trägt die Glocke überhaupt etwas bei?

Stand: 2026-09-19 · Auflage des Betreibers (2026-09-19) · **vor dem Lauf
geschrieben, danach nicht mehr angefasst**

Diese Seite entscheidet **nicht**, ob H5 richtig ist. Sie entscheidet, ob
H5 überhaupt registriert wird — und sie legt vorher fest, woran.

---

## Der Anlass

Die Diagnosespalte aus `docs/pilzampel-h1-ergebnis.md` zeigt bei allen
elf Arten: **der Regenfaktor allein trennt besser als der
Temperaturfaktor allein.** Beim Steinpilz (0,646 gegen 0,582) und beim
Pfifferling (0,630 gegen 0,557) ist der Regen allein so gut wie der volle
Score; bei Judasohr und Hallimasch macht die Glocke ein vorhandenes
Signal kaputt (0,629 → 0,539 und 0,593 → 0,490).

**Diese Spalte wurde auf P1 gerechnet, also DE ab 2019 — einer
Prüfachse.** Eine daraus abgeleitete Hypothese ist auf derselben Achse
entstanden, auf der sie geprüft werden wollte
(`docs/pilzampel-pruefachsen.md`).

Deshalb zuerst dieser Lauf, und zwar auf den **Anpassjahren DE ≤ 2018**.
Sie sind keine Prüfachse; dort wird ohnehin gefittet und diagnostiziert.
Der Lauf verbraucht nichts.

## Was gerechnet wird

Auf P3 (DE ≤ 2018), Design B, Messbasis `pinned`, Entdoppeln an, Seed 42
— dieselbe Ziehung wie in Phase 1.5, damit die Zahlen vergleichbar
bleiben.

Je Art drei Bewerter auf **denselben Paaren**:

| Bewerter | Formel |
|---|---|
| **voll** | `Regenfaktor · Glocke` — die ausgelieferte Ampel |
| **nur Regen** | `Regenfaktor` |
| **nur Temperatur** | `Glocke` |

Dasselbe für die **artgematchte Referenz** (dieselben ~10-km-Zellen,
dieselbe Monatsverteilung, Zielart ausgeschlossen). Und daraus die
Differenz Art minus Referenz je Bewerter, mit Vertrauensbereich —
gemeinsam über das Fundjahr gezogen, wie in N2.

## Die Entscheidung, vorab festgelegt

Betrachtet werden die **sechs ausgelieferten Arten**. Die übrigen fünf
laufen nachrichtlich mit.

### Bedingung 1 — die Zerlegung reist

> `B(nur Regen) > B(nur Temperatur)` bei **mindestens 5 der 6**.

Auf P1 war es 6 von 6 (und 11 von 11 über alle Arten). Fällt es auf P3
auseinander, war der P1-Befund jahresspezifisch.

### Bedingung 2 — die Glocke trägt nichts bei

> `B(voll) − B(nur Regen) < +0,020` bei **mindestens 5 der 6**.

Das ist dieselbe Latte, die H1 nicht genommen hat, nur umgedreht: Ein
Faktor, dessen Weglassen weniger als die Standardlatte kostet, trägt
nichts, was der Aufbau messen könnte.

### Bedingung 3 — die eigentliche Entscheidung

Regen wirkt auch auf den **Sammler**. Design B nimmt Ort und Jahreszeit
heraus, nicht die Wetterabhängigkeit des Suchens. Wenn die Referenz mit
einem Regen-Score genauso steigt wie die Art, ist nichts gewonnen.

Mit `Δ_regen = B_Art(nur Regen) − B_Referenz(nur Regen)` und
`Δ_voll = B_Art(voll) − B_Referenz(voll)`:

> **H5 wird registriert**, wenn beides gilt:
> - `Δ_regen > 0` mit Vertrauensbereich ohne die Null bei **mindestens 5
>   der 6**, und
> - `Median(Δ_regen) ≥ Median(Δ_voll) − 0,020`.
>
> **H5 wird NICHT registriert**, wenn eine der beiden verletzt ist.

Die zweite Hälfte ist die Falle, auf die es ankommt: Ein Regen-Score
kann die Art heben **und** die Referenz genauso, und dann stünde ein
größeres B über demselben Abstand. Nur der Abstand zählt.

## Was jeder Ausgang bedeutet

| Ausgang | Folge |
|---|---|
| **Alle drei erfüllt** | Die Idee ist ohne die Prüfjahre zu haben. H5 wird registriert; geprüft wird auf **AT+CH**, P1 zählt nur als Herkunftsangabe. |
| **Bedingung 1 oder 2 verletzt** | H5 wird **nicht** registriert. Der P1-Befund war dann vermutlich Rauschen oder jahresspezifisch — und das ist das Ergebnis, nicht ein Anlass für einen dritten Anlauf. |
| **Bedingung 3 verletzt** | H5 wird **nicht** registriert. Dann ist das Regensignal in dem Maß Suchaufwand, in dem es die Referenz mithebt, und eine Ampel ohne Temperatur sagte „es hat geregnet" — was der Nutzer selbst weiß. |

**Kein Zwischenergebnis wird nachverhandelt.** Fällt eine Bedingung
knapp, ist sie gefallen. Die Zahlen kommen in den Bericht, die Schwellen
bleiben, wie sie hier stehen.

## Was diese Seite nicht kann

- **Sie prüft nichts.** P3 sind die Anpassjahre; jede Zahl von dort ist
  eine Diagnose. Selbst ein glänzendes Ergebnis hier belegt H5 nicht —
  es erlaubt nur, H5 zu registrieren.
- **Sie trennt Suchaufwand und allgemeine Pilz-Wetterreaktion nicht**
  (A6). Die Referenz begrenzt beides zusammen nach oben.
- **Sie sagt nichts über die App.** Ohne Glocke leuchtete die Ampel im
  nassen Januar. Für ein Produkt wäre `R × Sperre` die realistische
  Variante, und die Saisonkurve daneben trüge einen Teil der Last. Das
  ist eine Frage für den Fall, dass H5 je besteht.

## Der Lauf

```
python3 tool/ampel_diagnose.py --zerlegung \
    --dataset pinned --dedupe \
    --api http://127.0.0.1:8080/v1/archive \
    --cache ~/pilzbuddy-ampel2000/ampel_cache_pinned \
    --seed 42 \
    --out docs/pilzampel-h5-vorpruefung-ergebnis.md
```
