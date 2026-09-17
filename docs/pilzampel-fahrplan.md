# Fahrplan: Pilzampel von der Glocke zum Modell

Stand: 2026-09-17 · Grundlage: `docs/pilzampel-*.md`, `tool/ampel_validate.py`, Skill `datenanalyse` (`references/pilzbuddy-ampel.md`)

Dieser Fahrplan ordnet die offenen Fragen in eine Reihenfolge, in der jede Messung auf einer festen Basis steht und keine die nächste entwertet. Er ist **kein Freibrief zum Ausprobieren**: Jede Hypothese wird vor ihrem Prüflauf schriftlich registriert, wie bisher.

---

## Ausgangslage

**Was trägt**
- Klasse `herbst` (13 °C) und `sommer` (17,5 °C, Hold-out AT+CH bestanden).
- Gepaarte AUC Steinpilz 0,762, Fliegenpilz 0,791, Maipilz 0,766; Placebo- und Spiegelkontrolle funktionieren.

**Was nicht trägt**
- `kalt` (−1 °C): in DE bestanden, im AT+CH-Hold-out gescheitert (Judasohr −0,066; Samtfußrübling mit verzerrter Spiegelkontrolle 0,467).
- `herbst_holz`: Hold-out gescheitert.
- Mit den vollständigen GBIF-Daten tauchen diese Probleme beim Klassenrechnen wieder auf.

**Befund, der vor allem anderen kommt**
`fetch_weather` fragt ohne `models=`. Die Vorgabe „best match" nimmt **bis 2016 ERA5-Land/ERA5 und ab 2017 IFS HRES** (`docs/pilzampel-openmeteo-lokal.md`). Die Trennlinie des Hold-outs liegt bei 2018/2019.

Damit werden Fenster auf überwiegend einem Instrument angepasst und auf einem anderen geprüft. Bei Winterarten (Frost, Tiefstwerte) und im Gebirge (AT/CH) ist ein Instrumentwechsel am ehesten spürbar. Jeder gescheiterte Hold-out ist deshalb nicht eindeutig deutbar, solange das nicht behoben ist.

**Leitgedanke der nächsten Schritte**
Nicht mehr Datenquellen, sondern die **richtige Verkettung** der vorhandenen:
- Wachstumsphase → Auslöser → Reifezeit
- Wasserbilanz statt gesetzter Regengewichtung

---

## Regeln, die für alle Phasen gelten

1. **Erkunden nur auf Anpassdaten** (DE, Jahre ≤ 2018). Prüfjahre (DE ≥ 2019) und AT+CH werden je Hypothese **einmal** berührt – nach der Registrierung. Wer Varianten am Hold-out ausprobiert, hat ihn verbraucht.
2. **Registrierung vor dem Prüflauf** in `docs/pilzampel-artenfenster.md` (oder eigener Datei), mit:
   - Latte,
   - Kontrollen,
   - „alle oder keine"-Regel bei Klassen.
3. **Entscheidende Messungen laufen stdlib-only in `tool/`**, mit Selbsttest. Exploration mit numpy/statsmodels ist erlaubt, aber außerhalb von `tool/`. Ihre Zahlen gelangen nie direkt in Konstanten.
4. **Spiegel-Regel:** Was ausgeliefert wird, steht identisch in `ampel_model.dart` und `tool/ampel_validate.py`; Fixtures neu erzeugen.
5. **Ein Neulauf, nicht fünf.** Alles, was den Wetter-Cache ungültig macht, wird in Phase 0 gebündelt.
6. **Abbruchregel:** Besteht eine Hypothese nicht, wird sie dokumentiert und nicht nachjustiert. Nach Phase 2 wird nur weitergemacht, wenn mindestens eine Hypothese bestanden hat.

---

## Phase 0 – Messbasis festziehen

Ziel: ein zeitlich konstantes Instrument und alle Variablen, die die Phasen 1–3 brauchen, in **einem** Cache-Neuaufbau.

### 0.1 Datensatz pinnen
- **Entscheidung des Betreibers.** Vorschlag:
  - Temperatur, Tagesminimum, Bodenfeuchte und Bodentemperatur aus `era5_land` (0,1°),
  - Niederschlag aus `era5` (0,25°),
  - **über alle Jahre gleich**. Zwei Instrumente sind unkritisch, solange keines mitten in der Reihe wechselt.
- Alternative: alles aus `era5`. Das ist gröber, aber ein einziges Instrument.
- Vor der Festlegung prüfen, ob die lokale Instanz die Variablen für das gewählte Modell liefert.
  - Kandidaten: `temperature_2m_mean`, `temperature_2m_min`, `precipitation_sum`, stündlich `soil_moisture_7_to_28cm` (→ Tagesmittel), `soil_temperature_0_to_7cm`, `snow_depth`.
  - Prüfweg: Stichprobe gegen den öffentlichen Dienst mit `models=`, analog `tool/openmeteo_local_check.py`.
- Kurz vergleichen, wie stark sich Vorgabe und gepinnter Datensatz unterscheiden, im Winter und in AT/CH. Das ist nur eine Tabelle und kein Tor, sie gehört aber in die Doku.

### 0.2 Stichprobe auf vollständige GBIF-Daten umstellen
- Quelle: lokaler Bestand (DOI `10.15468/dl.dwbsuf`), gleicher Filter wie bisher (`WHERE_USABLE`, Unsicherheit ≤ 1 000 m).
- Dubletten: höchstens **eine Meldung je Art × Melder × ~1 km × Tag**. Die vollständigen Daten verstärken Exkursions-Cluster; in typischen 5-km-Zellen stammen ~69 % der Meldungen von einer Person.
- `recordedBy` und `countryCode` je Paar mitführen.
- Den **vorzeichenbehafteten** Abstand zum Vergleichstag speichern (heute nur `abs`).

### 0.3 Vergleichstag-Abstand an das Modell koppeln
- Mindestabstand = längstes Fenster **des geprüften Modells**, nicht pauschal 26 Tage.
- Für Winterarten einen engeren Höchstabstand vorab festlegen, damit der Jahresgang die Spiegelkontrolle nicht verzerrt. Beispiel: Minimum = längstes Fenster, Maximum = Minimum + 10.
- Spiegel- und Placebokontrolle bleiben Pflicht, Toleranz ±0,03.

### 0.4 Referenzlauf
- Ausgelieferte Ampel (`herbst`, `sommer`, Schwellen) auf der neuen Basis nachrechnen: alle bisher gemessenen Arten, DE und AT+CH.
- **Erwartung, kein Tor:** Die Größenordnung bleibt (Steinpilz ~0,75). Große Verschiebungen werden als Instrumenteffekt dokumentiert, **bevor** etwas Neues gemessen wird.
- Schwellen neu messen; weichen sie ab, gelten die neuen erst nach Betreiberentscheidung.
- Kaltklasse mit ihrem bisherigen Fenster (−1 °C) einmal nachrechnen. Das klärt, ob der gescheiterte Hold-out am Instrument hing. Gilt als Nachmessung, nicht als neuer Hold-out-Versuch.

**Ergebnis Phase 0:** `docs/pilzampel-messbasis.md` mit Datensatzwahl, Variablenliste, Referenztabellen und Kontrollen.

---

## Phase 1 – Diagnosen ohne neues Modell

Alles auf **DE ≤ 2018**, stdlib, je eine kurze Tabelle.

**1.1 Richtungs-Split.** Gepaarte AUC getrennt nach „Vergleichstag vor" und „nach" dem Fund, je Art.
- Ähnliche Werte deuten auf eine Reaktion auf das Niveau.
- Deutliche Asymmetrie deutet auf eine Reaktion auf Änderung (Abkühlung, Frost).

**1.2 Frost-Vorlauf deskriptiv.** Anteil der Fund- bzw. Vergleichstage mit mindestens einem Frosttag (`Tmin ≤ 0 °C`) in den 7/14/21/28 Tagen davor, dazu Tage seit dem letzten Frost und Wärmesumme seitdem.
- Je Winterart als Verteilungsvergleich.
- Liefert die Startbereiche für 2.3 **ohne** Hold-out-Kontakt.

**1.3 Suchaufwand-Referenz.** Dieselbe Paarprüfung für „irgendeine Pilzmeldung am Ort" (Target Group, ohne die Zielart), je Saison.
- Die AUC der Referenz ist die Obergrenze des reinen Aufwandssignals.
- Artspezifisch belastbar ist nur, was darüber liegt.

**1.4 Melder-Abhängigkeit.** AUC ohne die 10 aktivsten Melder; Bootstrap über Melder × Jahr. Kippt eine Art dabei, wird sie markiert.

**Ergebnis Phase 1:** `docs/pilzampel-diagnosen.md`. Daraus werden die Hypothesen für Phase 2 registriert, mit festen Parameterbereichen.

---

## Phase 2 – Modellstruktur (je Hypothese registriert, einzeln geprüft)

Reihenfolge nach Aufwand und Erwartung. Jede Hypothese hat eine eigene Latte. Vorschlag für die Standardlatte:
- gepaarte AUC mindestens **+0,02** gegenüber dem Referenzlauf 0.4,
- in **≥ 70 % der Prüfjahre**, **und** Bootstrap-KI (über Jahre) der Differenz schließt 0 aus,
- Kontrollen sauber.

### H1 – Schmalere Temperaturglocke (`herbst`, `sommer`)
- Breite **3,25 K** statt 5 K (1/e-Halbbreite).
  - Herkunft: Nachrechnung der öffentlichen Bielefelder Tagesdaten (Skill, `scripts/bielefeld_refit.py`), nicht aus GBIF.
  - Deshalb sind **alle** DE-Jahre und AT+CH Prüfdaten.
- Bei Bestehen: Schwellen neu messen. Das 17,5-°C-Optimum der Sommerklasse ebenfalls auf DE ≤ 2018 neu anpassen und erneut in AT+CH prüfen, weil es mit 5 K bestimmt wurde.

### H2 – Feuchte aus Bodenfeuchte statt aus Regensumme (`herbst`, `sommer`)
- `F = Perzentil der mittleren Bodenfeuchte 7–28 cm über 14 Tage (Fensterlänge vorab wählen) in der Klimatologie DERSELBEN Zelle`.
  - Die Klimatologie wird nur aus Anpassjahren gebildet.
  - Ersetzt R; T unverändert.
- Parameter (Fensterlänge 7/14/21) auf DE ≤ 2018 wählen, dann registrieren.
- Erwartung: Vorteil vor allem nach Hitze- und Trockenphasen. Deshalb zusätzlich nach Jahren mit trockenem Spätsommer aufschlüsseln (beschreibend).

### H3 – Zwei-Phasen-Modell Winter (Samtfußrübling und Austernseitling getrennt)

```
Frost      = weiche Frostdosis in den letzten L Tagen, z.B. Σ max(0, θ − Tmin) / D
Reife      = Wärmesumme Σ max(0, Tmean − B) seit dem letzten Frosttag, gesättigt: 1 − exp(−GDD/F*)
Aufgetaut  = Mittel der letzten 3 Tage > 0 °C (weich: logistisch um 0 °C)
Feuchte    = R (oder H2, falls bestanden)
Score      = (1 − exp(−Frost)) × Reife × Aufgetaut × Feuchte
```

- Parameter: θ ∈ {0, −2, −4} °C, L ∈ {14, 21, 28} d, B ∈ {0, 3} °C, F* ∈ {10, 20, 40} K·d.
  - Gitter auf DE ≤ 2018, Plateaubreite berichten.
  - **Weiche Faktoren**, weil binäre Faktoren Gleichstände erzeugen, die als 0,5 zählen.
- Klassenbildung erst, wenn **beide** Arten einzeln bestehen.
- **Judasohr nicht in diese Hypothese.** Seine Fruchtkörper überdauern lange und quellen bei Feuchte wieder auf. Eigene Hypothese H3b: Feuchte-/Tauwetterereignis in den letzten 3–7 Tagen, ohne Frostauslöser.

### H4 – Temperatursturz im Herbst (optional)
- `Δt = Mittel(letzte 7 d) − Mittel(7 d davor)` als zusätzlicher, weicher Faktor zu T.
- Nur wenn 1.1 bei Herbstarten eine Asymmetrie zeigt.

**Ergebnis Phase 2:** je Hypothese ein Bericht im bestehenden Format (`Die Bedingung, die vor der Messung feststand` → `Gemessen` → `Der Ausgang`).

---

## Phase 3 – Gewichte schätzen statt setzen (nur nach mindestens einem bestandenen H)

- **Bedingtes Logit auf den Paaren**, stdlib per Newton, 2–5 Parameter. Liefert Standardfehler statt Gitter-Plateaus.
- **Gewicht Feuchte zu Temperatur:** Spalten `log F` und `log T`. Antwortet auf „Multiplikation oder anders?". Vergleich über die gepaarte Log-Likelihood.
- **Regengewichtung:** Regen in Altersblöcken (0–6, 7–13, 14–20, 21–25 d), falls H2 nicht bestanden hat.
- Ergebnis sind **Kandidaten** mit Standardfehler. Übernommen wird nur, was als neue Hypothese registriert und im Hold-out bestätigt ist.

---

## Phase 4 – Übernahme in die App

- Bestandene Klassen: Konstanten in `AMPEL_CLASSES` und `ampel_model.dart`, Schwellen neu gemessen, Fixtures, `test/ampel_model_test.dart`.
- Neue Wettervariablen (Tmin, Bodenfeuchte) brauchen den gleichen Datensatz auch in der App. Vor der Übernahme klären, woher die App sie live bekommt (Forecast-API mit `past_days`, gleiches Modell) und wie groß der Unterschied Reanalyse ↔ Vorhersage ist.
- `docs/pilzampel-formel.md` aktualisieren (Herkunftstabelle: gesetzt → gemessen).
- CHANGELOG, Feature-Branch, PR auf Englisch, Versionsregeln laut `CLAUDE.md`.

---

## Was bewusst nicht auf dem Plan steht

- **Habitat-Features** (Wald, Boden, Höhe): kürzen sich im Paardesign heraus. Sie gehören in ein späteres „Wo"-Modell, nicht in die Ampel.
- **Gradient Boosting / neuronale Netze:** An den Bielefelder Daten schlug ein Modell mit 24 Fenstern die Formel nicht. Erst sinnvoll, wenn Phase 2/3 den Strukturgewinn ausgeschöpft hat.
- **Kalibrierte Prozentangaben:** Das Paardesign liefert nur relative Effekte; die Ampel bleibt eine Tendenzanzeige.

## Checkpoints mit dem Betreiber

1. Nach 0.1: Datensatzwahl.
2. Nach 0.4: Referenzzahlen und Instrumenteffekt – erst dann Phase 1.
3. Vor jedem Prüflauf in Phase 2: registrierte Bedingung freigeben.
4. Vor Phase 4: Übernahme ja/nein.
