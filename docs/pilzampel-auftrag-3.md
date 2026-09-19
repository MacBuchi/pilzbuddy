# Auftrag 3: Sommer-Optimum und Schwellen

Stand: 2026-09-19 · gehört zu `docs/pilzampel-auftrag-2.md` und dessen Nachtrag
Anlass: Abschluss von H1/H5. Zwei Fragen sind offen geblieben, die eine angepasste Konstante brauchen — und die deshalb nie an der Reihe waren.

Es gilt weiter alles aus Auftrag 2: Erkunden nur auf P3, Registrierung vor jedem Achsenkontakt, Strichliste, Vorprüfung auf P3 vor jedem Achsenlauf, Methodenwechsel nach Datensicht in den Korrekturkasten, nichts an der ausgelieferten Ampel ohne Freigabe.

---

## A — Schwellen neu messen (keine Achse, zuerst)

Die vier Schwellen sind Quantile aus **Design A** und entscheiden, wie oft die App „günstig" sagt. Das ist eine Häufigkeitsfrage, keine Trennschärfefrage.

1. Schwellen als 50-/80-%-Quantil der Scores an **Design-B-Kontrolltagen** auf P3 neu messen, je Klasse.
2. Gegenüberstellen: heutige gegen neue Schwelle, und wie oft die Ampel je Art und Monat auf „günstig" bzw. „verhalten" stünde — alte und neue Werte nebeneinander.
3. Kein automatisches Übernehmen. Das ist eine Produktentscheidung und kommt als Vorlage.

Bericht: `docs/pilzampel-schwellen-designb.md`. **Checkpoint.**

## B — H6: Sommer-Optimum aus Design B

**Warum:** Die ausgelieferten 17,5 °C stammen aus Design A, wo bei einem Sommerfrüchter der Kalender mitgemessen wird. Das bedingte Logit sagt 13,16 ± 0,94 (clusterrobust), rund viereinhalb Standardfehler darunter; auf P3 trennt die Sommerglocke mit 0,512 praktisch nicht, der Regen derselben Art mit 0,632.

**Vorprüfung auf P3, ohne Achsenkontakt:**
1. Optimum per Logit **und** per Gitter auf P3 schätzen, mit clusterrobusten Fehlern. Stimmen beide Wege überein?
2. Stabilität: dasselbe auf den geteilten Anpassjahren (2006–12 / 2013–18). Wandert das Optimum um mehr als seinen Standardfehler, wird H6 **nicht** registriert.
3. Erwartete Effektgröße: Diskordanzanteil zwischen altem und neuem Score, daraus die Obergrenze für ΔAUC.
4. Auflösung: Jahres-Bootstrap der **Differenz** je Zug, nicht zwei Bänder.

**Checkpoint.** Erst danach registrieren.

**Registrierung, falls die Vorprüfung trägt:**
- Geprüft wird **ein** Wert, auf P3 festgelegt, danach eingefroren. Kein Gitter auf der Prüfachse.
- σ bleibt 5,0, die Herbstklasse bleibt unangetastet.
- Prüfachse: **AT + CH** (der Pfifferling hat dort 1876 Funde, mehr als in DE). DE ≥ 2019 als Bestätigung nur, wenn AT+CH besteht.
- Latte aus der gemessenen Auflösung, nicht aus dem Bauch — Verfahren wie bei H1, Mindestwert +0,010.
- Dritter Ausgang vorab benannt: Schließt das Band die Null ein, bleiben die 17,5 — nicht weil sie recht haben, sondern weil ohne Nachweis nichts geändert wird.
- Pflichtspalten wie bei H1: tote Funde, Placebo, Gegenprobe mit einem Optimum in die **andere** Richtung (z. B. 20 °C).

Bericht: `docs/pilzampel-h6-*.md`. **Checkpoint vor der Übernahme.**

## C — Nicht in diesem Auftrag

- Die Herbst-Optima. Fünf von fünf unter 13,0 ist ein Hinweis, kein Test; die Klasse ist ausgeliefert und trägt. Erst wenn H6 zeigt, dass ein Optimum aus Design B überhaupt hält.
- Die Alterung der Glocke zwischen 2013–18 und 2019–25. Jede Vertiefung benutzt P1.
- Neue Faktoren, neue Klassen, flexible Modelle.

## D — Erwartungshaltung, vorab festgehalten

Der artspezifische Anteil liegt bei knapp 0,07 über der Referenz. Ein besser sitzendes Optimum holt daraus realistisch 0,01 bis 0,03. Das ist in der Messung sichtbar und im Alltag kaum. Wer mehr will, braucht einen anderen Datentyp — Begehungen mit „nichts gefunden" aus der App.
