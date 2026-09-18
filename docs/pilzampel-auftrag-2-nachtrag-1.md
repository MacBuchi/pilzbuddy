# Nachtrag zu Auftrag 2 – nach Phase 1.5

Stand: 2026-09-18 · gehört zu `docs/pilzampel-auftrag-2.md`
Anlass: `docs/pilzampel-kontrolldesign.md` (Commit `fb6f2db`)

Phase 1.5 ist angenommen. Design B, die artgematchte Referenz, der Umgang mit den Randjahren und die Offenlegung der widerlegten eigenen Erwartung sind so, wie sie sein sollen. Dieser Nachtrag ändert eine registrierte Regel, schließt H3 ab und legt die nächsten Schritte fest.

---

## N1 – Die Evidenzstufen-Regel wird ersetzt (Regeländerung, offen deklariert)

**Was falsch war:** Abschnitt 5 von Auftrag 2 machte den Abschlag `A − B < 0,05` zur Bedingung für „belegt". Abschnitt 3 desselben Auftrags sagt aber, dass B aus zwei strukturellen Gründen kleiner sein **muss** (fehlende Kalenderkomponente; „üblich" schließt die guten Jahre ein). Die Latte bestraft damit den erwarteten Effekt und misst nicht die Belastbarkeit.

**Was dabei herauskam:** Der Pfifferling gilt als „belegt", weil sein A mit 0,643 wenig Kalender zu verlieren hatte. Nach Höhe von B und Abstand zur Referenz liegt der Steinpilz über ihm (0,647 / +0,063 gegen 0,629 / +0,054). Die Regel stellt die Rangfolge auf den Kopf.

**Neue Bedingung für „belegt"** – alle vier Punkte:

| Kriterium | Schwelle |
|---|---|
| Jahres-Bootstrap von B | schließt 0,50 aus |
| Differenz zur artgematchten Referenz | > 0, Vertrauensbereich ohne die Null (N2) |
| Funde in Design B | ≥ 150 |
| Kontrollen (Placebo B, Spiegel A) | innerhalb 2 SE |

**„vorläufig"**: B liegt über der Referenz und über 0,50, aber eine der vier Bedingungen wackelt.
**„keine Aussage"**: B erreicht die Referenz nicht oder der Bootstrap schließt 0,50 ein.

Der Abschlag `A − B` bleibt als Angabe in jeder Tabelle stehen – als Auskunft darüber, wieviel Kalender in der A-Zahl steckt, nicht als Tor.

**Umsetzung:** Stufen neu vergeben, die alte und die neue Zuordnung **nebeneinander** zeigen, mit diesem Abschnitt als Begründung. Erwartung nach Aktenlage (bitte nachrechnen, nicht übernehmen): belegt für Steinpilz, Birkenpilz, Pfifferling; vorläufig für Maronenröhrling, Fichtenreizker (Bootstrap streift 0,50) und Herbsttrompete (147 Funde); die fünf „keine Aussage" unverändert.

Dass diese Änderung **nach** dem Blick auf die Zahlen kommt, wird im Bericht so hingeschrieben. Sie ist vertretbar, weil sie kein Ergebnis umdeutet, sondern ein Kriterium ersetzt, das die falsche Größe gemessen hat – und weil sie die Anforderungen eher verschärft als lockert.

## N2 – Der Referenzabstand braucht einen Vertrauensbereich

Er trägt inzwischen die härteste Einzelentscheidung (Stockschwämmchen: B = 0,559 über der Schwelle, aber +0,001 gegen die eigene Referenz), steht aber als Punktschätzer ohne Streuung da. Bootstrap über Fundjahre für Art und Referenz, KI der Differenz berichten.

Dazu eine Korrektur im Text von `pilzampel-kontrolldesign.md`: Schwelle und Referenzabstand sind **nicht zwei unabhängige Kriterien**. Beide beruhen auf denselben B-AUCs. Sie sind zwei Blickwinkel, und der Referenzabstand ist der inhaltlich bessere.

## N3 – H3 und H3b werden geschlossen, mit einer Zahl statt eines Urteils

Nicht registrieren. Ergänze den Abschluss um die **nachweisbare Effektgröße**: Wie groß hätte ein Auslösereffekt bei der jeweiligen Paarzahl sein müssen, um bei 80 % Wahrscheinlichkeit sichtbar zu werden (Samtfußrübling 494, Austernseitling 451, Judasohr 783 Funde)? Dann steht dort „ein Effekt ab etwa +X AUC ist ausgeschlossen, ein kleinerer nicht" statt nur „nicht gestützt".

Die Feldbeobachtung zur kälteinduzierten Fruktifikation bleibt als offene Frage in der Doku stehen, nicht als widerlegte.

## N4 – Neue Prüfung: steckt ein Zeittrend in Design B?

Bei neun von elf Arten sind **spätere** Kontrolljahre leichter zu schlagen (+0,015 bis +0,060). Das ist systematisch und kann kein Instrumentwechsel sein, weil gepinnt wurde.

Prüfung, billig: die **Jahreszahl allein** als Score auf dieselben B-Paare, Fundjahr gegen Kontrolljahr. Liegt das deutlich über 0,50, enthält B einen Anteil „das Fundjahr liegt früh im Zeitraum" – vermutlich wärmere, trockenere Spätsommer, die unter der 13-°C-Glocke schlechter bewertet werden.

Ergebnis in einem Absatz. Bei deutlichem Befund als Vorschlag notieren (nicht umsetzen): Features als Abweichung von der zelleigenen Klimatologie statt als Absolutwerte.

## N5 – H1 ist die nächste Hypothese

Wie in Auftrag 2, mit drei Präzisierungen:

- **Maßgeblich ist Design B**, Anpassjahre DE ≤ 2018 bleiben unberührt: Die 3,25 K stammen aus den Bielefelder Daten, also sind alle GBIF-Jahre Prüfdaten.
- **Optimum bleibt fest bei 13,0 °C.** Nicht mitanpassen.
- **Der Pfifferling ist dabei.** Seine Kontrolle hält in B, und er hat den kleinsten Kalenderanteil aller Arten. Die Sommerklasse behält ihr eigenes Optimum; geprüft wird nur die Breite.
- **Zusätzlich, klar getrennt vom Test:** bedingtes Logit auf den B-Paaren der Anpassjahre mit `[log R, t, t²]`, um Optimum und Breite **mit Standardfehler** zu bekommen. Das ist Information für später und **nicht** der geprüfte Wert. Wer daraus den Testwert macht, verwandelt eine externe Zahl in eine angepasste – und deren Instabilität war der Befund aus Phase 0.4.

## N6 – Zwei Dokumentationsschulden

**`docs/pilzampel-formel.md`**: Dort steht die Kontrastgruppen-Erzählung mit dem Samtfußrübling („0,283 liegt deutlich unter dem Zufall … das Verhalten einer Temperaturnische"). Diese Zahl stammt aus Design A und ist nach Phase 1.5 überwiegend Kalender. Der Absatz bleibt, bekommt aber den Einordnungssatz und einen Verweis auf `pilzampel-kontrolldesign.md`.

**`ERGEBNISSE.md` im Austauschordner**: aktualisieren, `ergebnis-phase15-kontrolldesign.md` dazulegen, die überholte Empfehlung („H3 mit zwei Mitgliedern, vierfach gestützt") sichtbar als überholt markieren statt zu löschen.

## N7 – Evidenzstufen in der App (Produktentscheidung, hiermit getroffen)

- **Keine Warnung pro Art.** Fünf Hinweise auf sechs Arten lesen sich wie „kaputt", und dann wird auch der belastbare Teil abgewertet.
- **Eine Zeile auf Feature-Ebene** in der Ampel-Ansicht: experimentell, je Art unterschiedlich gut belegt.
- **Die Stufe selbst im Detailblatt der Art**, dort wo die Erklärung steht, mit einem Satz in Alltagssprache.
- Der Satz, der überall gilt, bleibt: Die Ampel bewertet **Bedingungen**, nicht Vorkommen.
- Umsetzung erst, wenn H1 durch ist – dann in einem Zug mit den dann gültigen Stufen und Schwellen.

---

## Reihenfolge

1. N1 und N2 (Stufen neu, Referenz-KI), N3 (Abschluss H3), N6 (Doku) – alles auf vorhandenen Läufen, kein neuer Hold-out-Kontakt.
2. N4 (Zeittrend-Prüfung), ein Absatz.
3. **Checkpoint.**
4. H1 registrieren (N5), Bedingung vorlegen, **Checkpoint**, dann Prüflauf.

Es wird weiterhin nichts an der ausgelieferten Ampel geändert.
