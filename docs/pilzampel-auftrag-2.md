# Auftrag 2 an Claude Code: Kontrolltag-Design klären, dann Phase 2

Stand: 2026-09-17 · Repo `MacBuchi/pilzbuddy`, Branch `feat/ampel-messbasis`
Vorlauf: `ergebnis-phase0-messbasis.md`, `ergebnis-phase1-diagnosen.md`, `pilzampel-fahrplan.md`, Skill `datenanalyse`

---

## 0. Haltung – bevor irgendetwas gemessen wird

Die Pilzampel ist ein **experimentelles Feature hinter einem Schalter**. Sie darf falsch liegen. Was sie nicht darf, ist so tun, als wüsste sie mehr, als sie weiß.

Daraus folgen vier Grundsätze, die über allen Regeln unten stehen:

1. **Nicht verwerfen, sondern beziffern.** Eine Art, deren Zahl unsicher ist, verliert ihre Ampel nicht automatisch. Sie bekommt eine niedrigere Evidenzstufe (Abschnitt 5). Löschen ist die Ausnahme, Einordnen die Regel.
2. **Keine veröffentlichte Zahl wird stillschweigend entwertet.** Wenn ein neues Design andere Werte liefert, stehen beide nebeneinander, mit der Erklärung, woher der Unterschied kommt. Ein Design ersetzt das andere erst nach Freigabe.
3. **Die Unsicherheit gehört in die Aussage, nicht in die Fußnote.** Jede Zahl mit Vertrauensbereich, jede Art mit Evidenzstufe, jede Klasse mit dem Satz, was sie nicht kann.
4. **Ein gescheiterter Hold-out schafft das Feature nicht ab, er begrenzt die Behauptung.** Aus „günstig für Art X" wird dann „günstige Pilzbedingungen allgemein" oder „keine Aussage" – aber nicht der Rückbau von etwas, das für andere Arten trägt.

Was aus Phase 0 und 1 **unverändert stehen bleibt**: die Datensatzwahl `era5_seamless`, das Entdoppeln, das Melder-Bootstrap, die Feststellung zur Instabilität der Optima, die veröffentlichten AUC-Werte der ausgelieferten Ampel. Diese Arbeit wird nicht wiederholt.

---

## 1. Der Befund, der diesen Auftrag auslöst

Phase 1.1 hat richtig erkannt, dass die gepaarte AUC bei vier Arten zu einem großen Teil die **Steigung des Scores über die Saison** misst. Der Bericht behandelt das als Randproblem dieser vier Arten. Es ist der Kern und betrifft drei Ergebnisse gleichzeitig:

- **Pfifferling** (vor 0,446 / danach 0,856): Ein Tag im Juli liegt näher an 17,5 °C als der Fundtag im September. Gemessen wird „es ist Hochsommer", nicht „das Wetter war gut".
- **Austernseitling** (vor 0,840 / danach 0,401): dasselbe gespiegelt.
- **1.2 hat damit kein sauberes Frostsignal.** Dass Samtfußrübling-Fundtage mehr Frost im Rücken haben als Tage 26–45 Tage daneben, folgt schon daraus, dass die Art mitten im Winter fruchtet und die Vergleichstage beidseitig Richtung Herbst und Frühjahr fallen. „Wärme seit Frost" (25 gegen 34 K·d) ist ebenfalls ein Niveaueffekt. **Auslöser und Niveau sind mit diesen Paaren nicht trennbar** – und genau das sollte H3 beantworten.
- **Der Kaltklassen-Hold-out erbt das.** Ein kaltes Fenster schlägt die 13 °C bei einer Winterart auch dann, wenn es nur den Kalender nachbildet. Die App zeigt die Saisonkurve ohnehin separat; ein Temperaturfenster, das nur die Saison umkodiert, fügt ihr nichts hinzu.

Das ist **kein Fehler der bisherigen Arbeit** – das Design war von Anfang an so registriert, und für die Herbstarten (Asymmetrie −0,04 bis +0,11) trägt es. Es ist eine Grenze, die jetzt sichtbar geworden ist.

---

## 2. Korrekturen am Messaufbau (vor Phase 2, ohne Hypothesenstatus)

**A1 – Zweites Kontrolltag-Design.** Siehe Abschnitt 3, das ist der Hauptauftrag.

**A2 – Kontroll-Toleranz an die Paarzahl koppeln.** ±0,03 ist eine feste Zahl an einer Größe, deren Streuung an `n` hängt: zwei Standardfehler sind ±0,045 bei 538 Paaren und ±0,022 bei 2000. Umstellen auf `2 · sqrt(0,25/n)`, den verwendeten Wert im Bericht ausweisen. Alte Läufe nicht rückwirkend umetikettieren, sondern in der Tabelle beide Grenzen zeigen.

**A3 – Aufwands-Referenz artgematcht ziehen.** Die 538 Paare stammen aus der allgemeinen, herbstlastigen Meldungsverteilung und werden nur mit einem anderen Fenster ausgewertet. Für Winterarten ist das keine faire Referenz. Neu: Referenzpaare je Zielart aus Meldungen **derselben Monate und derselben Orte** ziehen (Verteilung der Fundtage der Zielart als Gewicht), Zielart ausgeschlossen. Ergebnis je Art statt je Klasse.

**A4 – Die 3000er-Grenze in `_finds_from_local` aufheben oder zufällig ziehen.** Sie schneidet nach `gbifID`, also die jüngsten Einträge ab, und greift ausgerechnet beim Judasohr (3097 in DE). Danach das Judasohr einmal neu messen; die vier Befunde gegen es stammen alle aus derselben, möglicherweise beschnittenen Stichprobe – sie sind vier Blickwinkel, keine vier unabhängigen Tests.

**A5 – Spiegel-Kontrolle: die einfachere Erklärung prüfen.** Der Bericht schreibt die Wanderung dem Instrument zu, gestützt auf drei Arten mit wechselnden Vorzeichen und einer Rangkorrelation von −0,13. Die naheliegende Alternative liefert 1.1: Die Spiegelung kürzt eine **gerade** Steigung heraus, aber keine **Krümmung**. Prüfbar: Krümmung des mittleren Scores über die Saison je Art berechnen (zweite Differenz über Kalenderwochen) und gegen die Abweichung der Spiegel-Kontrolle von 0,5 auftragen. Erwartung: Pfifferling und Herbsttrompete liegen am Rand. Ergebnis in einem Absatz, kein eigener Bericht.

**A6 – Spalte „Überschuss" umbenennen in „Differenz zur Referenz"**, mit dem Satz aus 1.3, dass sie kein Abzugsposten ist.

---

## 3. Phase 1.5 – Doppel-Design (Hauptauftrag)

### Design A (bestehend)
Vergleichstag am selben Ort, **gleiches Jahr**, Abstand 26–45 Tage, Richtung zufällig. Bleibt unverändert und wird weiter berichtet.

### Design B (neu)
Vergleichstag am **selben Ort**, **gleiches Kalenderfenster** (Tag-des-Jahres ±7), **anderes Jahr**: zufällig aus den Jahren ±5 um das Fundjahr, gleich oft davor und danach gezogen, das Fundjahr ausgeschlossen. Nur Jahre, für die Wetter vollständig vorliegt; fehlende Jahre zählen und berichten, nicht still überspringen.

**Warum das die richtige Frage stellt:** Die Saison kürzt sich vollständig heraus statt nur ungefähr. Gemessen wird dann: *War das Wetter in diesem Jahr an diesem Datum besser als an diesem Datum üblich?* Genau das ist der Zusatznutzen, den die Ampel neben der ohnehin angezeigten Saisonkurve haben soll.

**Kontrollen für Design B:**
- Placebo: zwei Nicht-Fundjahre am selben Ort und Datum gegeneinander → Soll 0,5.
- Richtungs-Split: Kontrolljahr früher gegen später → deckt Klimatrend und Instrumentreste auf.
- Weiterhin Bootstrap über Jahre **und** über Melder.

**Bekannte Eigenschaften, die nicht als Fehler gewertet werden:**
- Die AUC-Werte werden **kleiner** als in Design A, weil die Kalenderkomponente fehlt. Das ist erwartet und kein Rückschritt.
- Bei Arten mit wenigen Fundjahren schrumpft die Paarzahl. Mindestens 150 Paare je Art, sonst als „zu dünn" ausweisen statt zu rechnen.

### Zu messen (DE, Jahre ≤ 2018, kein Hold-out-Kontakt)

Beide Designs, dieselben Arten wie in Phase 1, mindestens: Steinpilz, Maronenröhrling, Pfifferling, Hallimasch, Austernseitling, Judasohr, Samtfußrübling.

Ausgabetabelle je Art:

| Art | AUC Design A | AUC Design B | Differenz | Placebo A / B | Richtungs-Split A / B | Paare A / B |

Zusätzlich für die drei Winterarten die Frost-Diagnose aus 1.2 **in Design B wiederholen**. Erst dort ist ablesbar, ob die Frost-Signatur den Kalender überlebt.

### Was daraus folgt (vorab festgelegt, damit es keine nachträgliche Deutung wird)

- **Design B bestätigt A grob** (Differenz je Art < 0,05, Placebo sauber): Design A bleibt das Hauptmaß, B wird als Robustheitsangabe mitgeführt.
- **Design B fällt bei einzelnen Arten deutlich ab**: Für diese Arten ist Design A kalenderlastig. Sie behalten ihre Ampel, bekommen aber die Evidenzstufe „vorläufig" und im Bericht den Satz, wieviel der Trennschärfe Kalender ist.
- **Design B fällt bei einer Art unter 0,55**: Für sie gilt „keine artspezifische Aussage"; die allgemeine Pilzwetter-Aussage bleibt davon unberührt.
- Für die Hypothesen in Phase 2 ist **Design B maßgeblich**, weil sie Auslöser gegen Niveau unterscheiden sollen.

**Checkpoint.** Ergebnis als `docs/pilzampel-kontrolldesign.md`, dann anhalten.

---

## 4. Phase 2 – Hypothesen

Erst nach Freigabe von 1.5. Reihenfolge und Testachsen:

**Hold-out-Budget.** Es gibt zwei unabhängige Achsen: Zeit (DE ab 2019) und Geografie (AT, CH). Die Zweier-Kaltklasse entstand, **nachdem** die AT/CH-Ergebnisse gesehen wurden – sie dort erneut zu prüfen, wäre ein zweiter Blick auf dieselben Daten. Deshalb:
- H3 und H3b werden auf **DE ab 2019** registriert und geprüft.
- **AT+CH bleibt reserviert** als letzte Instanz vor einer Auslieferung.
- Jede Hypothese berührt ihre Prüfachse genau einmal.

### H3 – Zwei-Phasen-Wintermodell (Samtfußrübling, Austernseitling)
- Formel und Parametergitter wie im Fahrplan, weiche Faktoren.
- **Parameterbereiche erst nach 1.5 festlegen**, aus der Frost-Diagnose in Design B. Die Startwerte aus 1.2 (L eher lang, F* ≈ 25 K·d) stehen unter Vorbehalt.
- Vergleichsmaßstab: die ausgelieferte Ampel **und** die reine Kaltglocke (−2,5 °C) auf denselben Paaren. Nur so ist sichtbar, ob das Zwei-Phasen-Modell etwas über „im Winter ist es kalt" hinaus leistet.
- Latte: +0,02 gepaarte AUC gegenüber der Kaltglocke, in ≥ 70 % der Prüfjahre, Bootstrap-KI über Jahre ohne die Null, Kontrollen innerhalb 2 SE.
- **Teilerfolg ist ein Ergebnis:** Besteht nur eine der beiden Arten, wird sie einzeln ausgewiesen; eine Klasse entsteht daraus nicht.

### H3b – Judasohr als Feuchte-Hypothese
- Erst nach A4 (Stichprobengrenze) messen.
- Auslöser: Niederschlag oder Bodenfeuchteanstieg in den letzten 3–7 Tagen, kein Frostterm; Temperatur nur als Ausschluss (gefroren = keine Fruktifikation).
- Gleiche Latte. Besteht sie nicht: „keine Aussage" für diese Art, dokumentiert.

### H1 – Schmalere Glocke (3,25 K)
- Herkunft extern (Bielefeld), deshalb sind alle GBIF-Jahre Prüfdaten.
- Gilt für `herbst` mit festem Optimum 13,0 °C. **Das Optimum wird nicht mitangepasst** – Phase 0.4 hat gezeigt, dass angepasste Optima auf wenigen hundert Paaren um bis zu 3 K wandern.
- Der Pfifferling bleibt außen vor, solange seine Kontrolle nicht hält.
- Latte wie oben, zusätzlich: Schwellen werden nach Bestehen neu gemessen und als Produktentscheidung vorgelegt.

### H2 – Feuchte aus Bodenfeuchte
- Wie im Fahrplan (Perzentil der zelleigenen Klimatologie, nur Anpassjahre).
- Nach H1, weil beide denselben Score verändern.

### H4 – Temperatursturz
- Nur, wenn 1.5 bei Herbstarten in Design B eine Asymmetrie zeigt.

---

## 5. Unsicherheit ausweisen statt Zahlen verwerfen

Das ist der Teil, der mir am wichtigsten ist. Jede Art bekommt eine **Evidenzstufe**, die in `docs/` und später in der App steht:

| Stufe | Bedingung | Was die App sagen darf |
|---|---|---|
| **belegt** | Hold-out bestanden, Design A und B tragen, Kontrollen innerhalb 2 SE, ≥ 300 Paare | Ampel mit drei Stufen wie heute |
| **vorläufig** | Effekt vorhanden, aber eine Bedingung wackelt (Design B schwächer, Kontrolle am Rand, dünne Paarzahl) | Ampel mit Hinweis „unsichere Datenlage für diese Art" |
| **keine Aussage** | kein Effekt nachweisbar oder Kontrolle verletzt | keine Ampel, Saisonkurve bleibt |

Dazu:
- **Jede AUC im Bericht mit Vertrauensbereich** (Jahres-Bootstrap als konservativer Wert, Melder-Bootstrap daneben).
- **Optima und Breiten künftig mit Standardfehler schätzen**, nicht per Gitter: bedingtes Logit auf den Paaren mit `[log F, t, t²]` (Referenz `fit_paired_logit` im Skill, stdlib-Fassung im Selbsttest gegengeprüft). Optimum `= −b_t/(2 b_t²)`, Breite `= sqrt(b_logF / −b_t²)`. Eine flache Likelihood ist dann sichtbar, statt sich als scheinpräziser Gitterpunkt zu tarnen.
- **Die Differenz zur Aufwands-Referenz** (A3) gehört je Art in den Bericht, mit dem Satz aus 1.3: Das Design kann Suchaufwand und allgemeine Pilz-Wetterreaktion nicht trennen. Der ehrliche Satz über die Ampel lautet „heute ist Pilzwetter", nicht „hier steht diese Art".
- In `docs/pilzampel-formel.md` die Herkunftstabelle nachziehen: was inzwischen gemessen ist, was weiterhin gesetzt ist.

---

## 6. Was ausdrücklich nicht passiert

- **Kein Rückbau der ausgelieferten Ampel** ohne Freigabe – auch nicht, wenn Design B kleinere Zahlen liefert.
- **Keine gelöschten Berichte.** Frühere Messungen bleiben stehen und bekommen einen Einordnungssatz.
- **Kein Nachjustieren nach Blick auf Prüfdaten.** Wer Parameter ändert, registriert neu und verbraucht eine Prüfachse.
- **Keine neuen Datenquellen** über die in Phase 0 beschafften Variablen hinaus.
- **Keine flexiblen Modelle** (Boosting, Netze), solange Phase 2 läuft.

---

## 7. Ablauf und Berichte

1. A2, A4, A6 umsetzen (klein, stdlib, Selbsttest). A5 als Absatz.
2. A1/A3 bauen, Phase 1.5 rechnen → `docs/pilzampel-kontrolldesign.md` → **Checkpoint**.
3. Parameterbereiche für H3/H3b aus 1.5 ableiten, Bedingung registrieren → **Checkpoint**.
4. Prüflauf H3, Bericht im bestehenden Format → **Checkpoint**.
5. Danach H3b, H1, H2 in dieser Reihenfolge, je mit eigener Registrierung.

Berichtsformat unverändert: „Die Bedingung, die vor der Messung feststand" → „Gemessen" → „Der Ausgang". Jede Tabelle mit Paarzahl, Vertrauensbereich, Kontrollwert und verwendeter Toleranz.

Am Ende jeder Arbeitseinheit: was gemessen wurde, welche Bedingung galt, ob sie erfüllt ist, welche Evidenzstufe sich daraus für welche Art ergibt, Branch- und Commit-Stand.

**Wenn eine Messung dem Plan widerspricht: anhalten und berichten, nicht umplanen.**
