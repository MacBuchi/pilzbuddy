# Gemessene Niederschlagsdaten für Österreich, die Schweiz und Norditalien

Stand: 2026-10-01 · Recherche und Messung, **noch kein Einbau** ·
Anlass: Modellgitter des Alpenraums (#612, `tool/model_weather.py`)

## Die Frage

Außerhalb Deutschlands kommt der Regen in der App seit 1.212.0 aus dem
Wettermodell (Open-Meteo, ICON-D2, 12-km-Raster). Am 2026-10-01 lag die
14-Tage-Summe des Modells an der Radargrenze bei Salzburg bei 28 mm, das
Radar bei 51 mm. Der Betreiber will für die Vergangenheit gemessene Werte
statt Modellwerten. Gesucht waren tägliche Niederschlagssummen als
Gitter, gemessen oder aus Messungen gerechnet, für Österreich, die
Schweiz mit Liechtenstein und Norditalien, mit mindestens 30 Tagen
Rückblick und höchstens 1–2 Tagen Verzug.

## Ergebnis in Kürze

| Land | Quelle | Art | Verzug (gemessen) | Lizenz |
|---|---|---|---|---|
| Österreich | **GeoSphere INCA** (stündlich, zu UTC-Tagen summiert) | Analyse aus Stationen und österreichischem Radar | ~30–40 min je Stunde | CC BY 4.0 |
| Schweiz, Liechtenstein | **MeteoSchweiz RprelimD** (vorläufiges Tagesgitter) | Stationen, interpoliert | Tag D um D+1 12:17 UTC | CC BY 4.0 |
| Italien | **DPC „Merging“ CUM24** (Radar + Regenmesser, MCM) | Radar mit Stationen verschmolzen | ~20 min nach 00:00 UTC | **CC BY-SA 4.0** |
| Deutschland | DWD RADOLAN (unverändert) | Radar, mit Stationen angeeicht | wie bisher | wie bisher |
| übrige Box (SI, CZ, SK, HU, FR) | Modell (unverändert) | – | – | CC BY 4.0 |

Drei Befunde tragen die Empfehlung:

1. **Das Modell liegt in Österreich rund 20 % zu niedrig.** Über 26
   Tage (09-04 bis 09-29) und 1 436 Rasterpunkte gilt: Modell zu INCA
   Median 0,80, Modell zu SPARTACUS 0,79. Der Fall Salzburg ist also
   kein Einzelfall. In der Schweiz ist das Modell unverzerrt
   (Modell zu RprelimD 1,02), in der italienischen Alpenbox ebenfalls
   kaum (Modell zu DPC 0,94), dort aber mit großer Streuung je Ort.
2. **Die beiden österreichischen Gitter stimmen überein, obwohl sie
   verschieden gebaut sind.** INCA (Stationen und Radar) und SPARTACUS
   (nur Stationen) liegen über 1 335 Punkte bei Verhältnis 1,02 und
   r = 0,91.
3. **Jenseits der Grenze ist das DWD-Radar schlechter als die nationalen
   Daten.** In Bayern stimmen DWD-Radar und INCA überein (Verhältnis
   1,00, r = 0,90, 389 Punkte). In Österreich fällt das DWD-Radar gegen
   INCA auf 0,85 bei r = 0,58, und zwar umso stärker, je weiter der Ort
   von Deutschland weg ist. Daraus folgt eine andere Reihenfolge als
   ursprünglich angenommen:

   **nationale Messung im eigenen Land > DWD-Radar > Modell.**

   Innerhalb Deutschlands ändert sich nichts, weil dort keine der
   nationalen Quellen gilt. Außerhalb ist das Radar nur noch dort im
   Spiel, wo kein nationales Gitter liegt (Grenzstreifen nach
   Tschechien und Frankreich).

## Wie gemessen wurde

Alle Abrufe am 2026-10-01 von einem Rechner des Betreibers aus, ohne
Konto. Fenster: 30 Tage bis 2026-09-29 (also ab 08-31). Verglichen wird
mit unserem Spiegel `rain-data-mirror`: Radarstapel `rain_day_*` (26
Tage, 09-04 bis 09-29) und Modellstapel `model_rain_*` (09-03 bis
09-30), dekodiert wie `lib/features/map/rain_grid.dart` (Zeilen-Delta,
gzip, 255 = keine Daten).

- **Orte:** je Quelle die nächstgelegene Zelle. **Fläche:** je Quelle
  der Wert an jedem der 3 574 Punkte des Modellrasters (12 km, Box ohne
  Deutschland), Summe über 26 Tage, nur Punkte mit allen 26 Tagen. Die
  Länderzuordnung je Punkt stammt aus dem lokalen GBIF-Bestand
  (Mehrheit der `countryCode` im Umkreis von ~6 km). „IT“ heißt deshalb
  die italienische Alpenbox 6,6–13,9° O, 45,6–47,2° N, dazu 728
  Punkte „sonstige“ (SI, CZ, SK, HU, FR, Grenzsäume).
- **Tagesgrenzen:** Radar, Modell, INCA, CombiPrecip und DPC meinen den
  UTC-Tag 00–24. SPARTACUS und RprelimD rechnen von 06 bis 06 UTC und
  tragen das Datum des Beginns. Gegengeprüft über die Korrelation der
  Tageswerte mit INCA bei Versatz −1/0/+1: Alle Quellen passen bei 0 am
  besten; die beiden 06–06-Quellen zeigen den erwarteten Überlauf in den
  Vortag (r 0,36/0,44 gegen 0,01/0,01 in den Folgetag).
- Die Auswerteskripte nutzen numpy, xarray, h5py, rasterio und pyproj
  und liegen nicht im Repo. Für den Einbau sind sie nicht die Vorlage,
  siehe „Was der Einbau braucht“.
- **OPERA nachgemessen:** Der 30-Tage-Abruf scheiterte zunächst an der
  Leitung des Rechners (0,4–7 KB/s bei allen Hosts). Nachgeholt am
  selben Tag auf einem GitHub-Runner: 720 von 720 Stundendateien, keine
  fehlende Stunde, 2,1 s je Datei (#646, Kommentar
  https://github.com/MacBuchi/pilzbuddy/issues/646#issuecomment-5930869089,
  Dateien auf dem Branch `measure/opera-alps`). Der Flächenvergleich
  gegen die lokal vorliegenden Gitter ist danach hier gerechnet.

## Die Quellen im Einzelnen

### Österreich: GeoSphere Austria, INCA (empfohlen)

| Kriterium | Wert |
|---|---|
| Datensatz | `inca-v1-1h-1km`, „INCA analysis – large domain“, DOI https://doi.org/10.60669/6akt-5p05 |
| Art | Analyse: Stationen (TAWES) und österreichisches Radar auf einem Modellfeld als Hintergrund. Die NetCDF-Datei sagt `source: modeled data` — das ist der Hintergrund, nicht das Ergebnis; in Österreich stimmt INCA mit dem reinen Stationsgitter SPARTACUS überein (r 0,91). |
| Abdeckung | 45,77–49,48° N, 8,10–17,74° O (API-Metadaten; die Datensatzseite nennt 7,1° O). Ganz Österreich, Bayern-Süd, Ostschweiz, Südtirol, Trentino-Nord. 2 682 von 3 574 Rasterpunkten. |
| Auflösung, Projektion | 1 km, 701 × 401, MGI / Austria Lambert (EPSG:31287) |
| Format | NetCDF4 (HDF5) oder GeoJSON; Variable `RR`, 1-Stunden-Summe in kg m⁻² |
| Abfrageform | ganzes Gitter je Zeitraum und Box: `GET https://dataset.api.hub.geosphere.at/v1/grid/historical/inca-v1-1h-1km?parameters=RR&start=…&end=…&bbox=…&output_format=netcdf`; auch Zeitreihe je Punkt (nicht gebraucht) |
| Tagesdefinition | stündlich, frei zu UTC-Tagen summierbar — passt genau zum Radarstapel |
| Verzug | Stunde 09:00 UTC lag um 09:37 UTC vor, Stunde 10:00 um 10:30 (Metadaten). Gestern ist also ab ~00:40 UTC vollständig. |
| Historie | ab 2011-03-15 |
| Anfragegrenzen (gemessen) | 5 Anfragen/s, **240 Anfragen/h** (Header `x-ratelimit-limit-second/-hour`); **10 000 000 Datenpunkte je Anfrage** (Antwort 400: „The data slice you requested is too large. The limit is 10000000 data points.“). Ein Tag über die ganze Domäne sind 24 × 281 101 = 6,7 Mio., also **eine Anfrage je Tag**; 30 Tage = 31 Anfragen. |
| Größe | Download 0,78–4,9 MB je Tag (NetCDF, ganze Domäne); GeoJSON wäre 38 MB je Tag |
| Lizenz | „Creative Commons Attribution 4.0 International“ (Datensatzseite https://data.hub.geosphere.at/dataset/inca-v1-1h-1km) |

### Österreich: GeoSphere Austria, SPARTACUS v3 (Prüfstein)

| Kriterium | Wert |
|---|---|
| Datensatz | `spartacus-v3-1d-1km`, DOI https://doi.org/10.60669/5cqg-p427 |
| Art | **reine Stationsinterpolation**. Seit v3 mit Auslandsstationen: 105 eigene, 24 Südtirol, 18 DWD, 13 MeteoSchweiz, 10 Meteotrentino, 7 ARSO, je wenige CHMI/HungaroMet/SHMU (`SPARTACUS-v3_stations.csv`) |
| Abdeckung | 46,16–49,18° N, 9,39–17,38° O; Österreich und Saum, dazu Südtirol. 1 494 Rasterpunkte. Die 101 österreichischen Punkte ohne Wert liegen fast alle an der Ost- und Südostgrenze (14–17° O; zum Teil Grenzpunkte, die die GBIF-Zuordnung Österreich zuschlägt). |
| Auflösung, Projektion | 1 km, 584 × 329, ETRS89 / Austria Lambert (EPSG:3416) |
| Format, Abfrage | wie INCA, eine Anfrage für 31 Tage (1,67 MB NetCDF) |
| Tagesdefinition | „07:00 UTC+1 of the respective day and 07:00 UTC+1 of the following day“, also 06–06 UTC, Datum = Beginn |
| Verzug | Tag 09-30 (endet 10-01 06 UTC) lag um 09:37 UTC vor, Datensatz geändert 09:48 UTC |
| Historie | ab 1961 |
| Grenzen | wie INCA |
| Lizenz | „Creative Commons Attribution 4.0 International“ |

SPARTACUS ist das, was „gemessen“ im engsten Sinn heißt, hat aber zwei
Nachteile gegenüber INCA: die 06–06-Tage, die neben den UTC-Tagen des
Radarstapels eine Naht ergeben, und kein Radar, also keine Gewitterzellen
zwischen den Stationen (Gmunden 09-24: INCA 21 mm, Radar 4, SPARTACUS 7 —
der eine Tag, an dem die beiden auseinanderliegen). Empfohlen als
**`--verify`** des INCA-Stapels: 26-Tage-Summen an Stichproben-Punkten
gegen SPARTACUS, Abbruch bei systematischer Abweichung.

### Schweiz und Liechtenstein: MeteoSchweiz RprelimD (empfohlen)

| Kriterium | Wert |
|---|---|
| Datensatz | STAC-Collection `ch.meteoschweiz.ogd-surface-derived-grid`, Asset `…rprelimd_ch01h.swiss.lv95_<JJJJMMTT>000000_….nc` |
| Art | Stationsinterpolation („daily precipitation sum (preliminary)“, Schiemann et al. 2010). Endgültig als **RhiresD** im Monatsitem (`…-last.rhiresd…`), etwa vier Wochen nach Monatsende (Item 2026-06 zuletzt am 07-26 geändert). |
| Abdeckung | Schweiz und Liechtenstein, dazu Säume: Bregenz, Feldkirch, Konstanz, Como haben Werte, Bormio nicht. 63 185 gültige von 98 050 Zellen; 821 Rasterpunkte (685 von 706 in CH). |
| Auflösung, Projektion | 1 km, 370 × 265, CH1903+ / LV95 (EPSG:2056) |
| Format | NetCDF4, float32, 1,21 MB je Tag (konstant) |
| Abfrageform | ein Item je Tag: `GET https://data.geo.admin.ch/api/stac/v1/collections/ch.meteoschweiz.ogd-surface-derived-grid/items/<JJJJMMTT>-ch`, darin der Link auf die Datei; kein Schlüssel |
| Tagesdefinition | 06–06 UTC, Datum = Beginn (durch den Versatztest bestätigt) |
| Verzug | alle 30 Tage gleich: Tag D erscheint am **D+1 um 12:17 UTC** (Asset-Feld `updated`) |
| Historie | Tagesitems ab 2026-08-02 (61 Tage, Item-Feld `expires`), davor nur Monatsitems mit RhiresD |
| Anfragegrenzen | keine Kopfzeilen (CloudFront/S3); Nutzungsbedingungen verbieten „excessive use in terms of access frequency or data volume“. Ein Abruf je Tag ist unkritisch. |
| Lizenz | CC BY 4.0, Wortlaut siehe Lizenzpflichten |

### Schweiz: MeteoSchweiz CombiPrecip (nicht empfohlen)

| Kriterium | Wert |
|---|---|
| Datensatz | `ch.meteoschweiz.ogd-radar-precip`, Dateien `cpc<JJ><TTT><HHMM>0_00060.001.h5` |
| Art | Radar, mit Schweizer Regenmessern angeeicht (270 Stationen je Stunde, im Dateikopf) |
| Abdeckung | 710 × 640 km, 2,7–12,5° O, 43,6–49,4° N; angeeicht nur in der Schweiz |
| Auflösung, Projektion | 1 km, Swiss Oblique Mercator (`+proj=somerc`, LV95-Koordinaten) |
| Format | ODIM-HDF5, eine 60-Minuten-Summe **alle 5 Minuten** (288 Dateien je Tag), 45–205 KB je Datei; ein Tag = 24 Dateien |
| Verzug | ~4 min (`prod_date` 01:03:43 für 01:00) |
| Historie | **nur 14 Tage rollierend** (Items 09-17 bis 10-02 am 10-01, je Item `expires` am Folgetag; die zwei ältesten Tage schon unvollständig) |
| Urteil | Für 30 Tage Rückblick müsste man täglich ernten. Außerhalb der Schweiz liegt es weit unter allen anderen Quellen (Kufstein 09-24: 3,7 mm, sonst 12–14). In der Schweiz bringt es gegenüber RprelimD nur die UTC-Tage. |

### Italien: Dipartimento della Protezione Civile, „Merging“ CUM24 (empfohlen)

| Kriterium | Wert |
|---|---|
| Produkt | Typ `CUM24` der Radar-DPC-API, Datei `rete_terra/MCM/cum24h/Merging_<JJJJMMTTHHMM>_24h.tif` |
| Art | „cumulative rainfall … by integrating radar network data with data from ground-based pluviometric stations“ (Radar-Plattform), Verfahren Modified Conditional Merging (MCM); wird bei verspäteten Stationsdaten neu gerechnet |
| Abdeckung | ganz Italien, 5,6–19,0° O, 35,25–47,58° N; alle 690 Punkte der Alpenbox. Außerhalb Italiens unbrauchbar, siehe Flächenvergleich. |
| Auflösung, Projektion | 0,01°, 1 341 × 1 233, WGS84 (EPSG:4326) |
| Format | GeoTIFF float32, deflate, Kacheln 256 × 256, nodata −9999; 34 KB–1,7 MB je Tag (ganz Italien) |
| Abfrageform | `GET https://radar-api.protezionecivile.it/findLastProductByType?type=CUM24`, dann `POST …/downloadProduct` mit `{"productType":"CUM24","productDate":<ms>}` und Kopfzeile `Origin` (ohne wird abgelehnt) → vorsignierte S3-URL, 900 s gültig |
| Tagesdefinition | 24 h bis zum Zeitstempel; die Datei von D+1 00:00 ist der UTC-Tag D (Versatztest) |
| Verzug | alle 30 min neu; der Stand 09:30 UTC lag um 09:51 UTC vor |
| Historie | **ab 2026-05-15** (Bisektion am 10-01, davor HTTP 500 / S3 403). Die Oberfläche spricht von 14 Tagen — die API reicht weiter. Ob das ein fester Beginn oder ein rollierendes Fenster ist, ist offen. |
| Anfragegrenzen | keine Kopfzeilen; ein Tag = 2 Aufrufe |
| Lizenz | **CC BY-SA**, Quelle „Radar-DPC“ |

### Europaweit: EUMETNET OPERA, Open Radar Data (nicht empfohlen)

| Kriterium | Wert |
|---|---|
| Produkt | `OPERA@<JJJJMMTTTHHMM>@0@ACRR.h5`, „OPERA NIMBUS 1-hour accumulation composite“ |
| Zugang | anonym aus S3: `https://s3.waw3-1.cloudferro.com/openradar-archive/<JJJJ>/<MM>/<TT>/OPERA/COMP/` (Archiv, September 2026 vollständig gelistet) und `openradar-24h` (24 h); API über MeteoGate |
| Format, Raster | ODIM-HDF5, 2 km, 1 900 × 2 200, Lambert Equal Area, ganz Europa; eine 1-h-Summe alle 15 min, 1,6–1,8 MB je Datei; ein Tag = 24 Dateien ≈ 40 MB |
| Verzug | ~10 min (Datei 12:00 am 12:10 geschrieben) |
| Lizenz | CC BY 4.0 (im Dateikopf: `license = https://creativecommons.org/licenses/by/4.0/`), Rechte bei EUMETNET |
| **Ausschlussgrund** | Im Komposit vom 2026-09-24 12:00 stecken 164 Radare — **kein österreichisches, kein italienisches** (Liste `how/nodes`). Österreich und Norditalien sieht OPERA nur vom Rand aus deutschen, Schweizer, tschechischen und slowenischen Radaren, ohne Stationsangleich. In der Schweiz ist RprelimD die bessere Quelle. |
| **Gemessen** (26 Tage, Raster) | Österreich gegen INCA 0,81 / r 0,36 (1 391 Punkte) — nördlich 47,3° N 0,93 / r 0,60, südlich 0,37 / r 0,26. Schweiz gegen RprelimD 0,72 / r 0,45. Italien gegen DPC 0,50 / r 0,57. Störechos ungefiltert: bis 1 143 mm in 26 Tagen (Karawanken), 531 mm westlich von Innsbruck. |
| **Gemessen** (Orte, 26 Tage) | Salzburg 69, Kufstein 46, Gmunden 101, Zell am See 86, Innsbruck **110** (INCA 66), Bregenz 41, Bozen **12** (INCA 60), Brixen 17, Chur **2** (RprelimD 22), Luzern 24, Davos 44 mm |

### Italien: Regionaldienste (nicht gemessen)

| Dienst | Was es gibt | Lizenz | Gitter? |
|---|---|---|---|
| Provinz Bozen, Wetterdienst | Open-Data-API, ~120 Echtzeitstationen; Radar nur als 15 aktuelle Bilder (`api-weather.services.siag.it/api/v2/radar/…`) | CC0 (CKAN `data.civis.bz.it`) | nein |
| Meteotrentino | Stationsreihen | CC BY 4.0 (laut Katalog) | nein |
| ARPA Lombardia | Sensoren über `dati.lombardia.it` (Socrata) | nicht geprüft | nein |
| ARPAV (Venetien) | Stationen | CC-BY-kompatibel (laut Ankündigung 2011) | nein |
| ARPA FVG (OSMER) | Stationen | nicht geprüft | nein |
| ARPA Piemonte | Stationen, Geoportal | nicht geprüft | nein |
| Aostatal (Centro funzionale) | Stationen | nicht geprüft | nein |

Kein Regionaldienst liefert nach dieser Recherche ein Tagesgitter. Für
uns wären es Punktabfragen je Station und Region, also sieben Pipelines
— genau das, was „wer Hunderte Einzelabfragen braucht, stellt die
falsche Frage“ ausschließt. Das DPC-Produkt bündelt Radar und
Stationsnetze bereits; Südtirol und Trentino gehen zudem in SPARTACUS
ein.

### Ausgeschlossen aus anderen Gründen

| Quelle | Grund | Wen man fragen müsste |
|---|---|---|
| E-OBS (ECA&D, auch als Tagesupdate bei KNMI) | Datenpolitik: „strictly for use in non-commercial research and education projects only“ — NC, für Assets ausgeschlossen | ECA&D-Team, eca@knmi.nl. Wortlaut siehe unten. Nicht angefragt. |
| H-SAF (z. B. H05B) | nur mit Konto (Registrierung, FTP `ftphsaf.meteoam.it`); Satellit, kein Stationsangleich in Echtzeit | Selbstregistrierung auf hsaf.meteoam.it; nicht angelegt |
| GPM IMERG Late | Konto (NASA Earthdata Login); Satellit, 0,1°, 14 h Verzug | Selbstregistrierung; nicht angelegt |
| ERA5-Land | Modell, ~5 Tage Verzug | – |

Anfrage an ECA&D, falls E-OBS je in Frage käme (nicht gesendet):

> Dear ECA&D team, we develop a free, non-commercial, open-source
> mushroom-foraging app (PilzBuddy). We would like to show daily
> precipitation sums for the Alps derived from the daily-updated E-OBS
> RR grid, aggregated and quantised to 1 mm, inside the app. Does this
> fall under "non-commercial research and education" in your data
> policy, and which attribution do you require? Kind regards

## Die Messung an den Orten

Summen in mm. In Klammern die Zahl der Tage mit Wert, wenn Tage fehlen;
„–“ heißt, die Quelle deckt den Ort nicht ab. Das Modell fehlt an
08-31 bis 09-02, das Radar an 08-31 bis 09-03 — in den 30-Tage-Summen
also nicht vergleichbar, deshalb zusätzlich die 26 Tage, in denen alle
lückenlos sind. SPARTACUS und RprelimD rechnen 06–06 UTC.

**26 Tage (09-04 bis 09-29), fairer Vergleich:**

| Ort | Radar DWD | Modell | INCA | SPARTACUS | RprelimD | CombiPrecip | DPC |
|---|---|---|---|---|---|---|---|
| Salzburg | 95 | 68 | 78 | 81 | – | – | – |
| Kufstein | 88 | 93 | 86 | 85 | – | 4 (11/26) | 9 |
| Gmunden | 113 | 67 | 128 | 91 | – | – | – |
| Zell am See | 53 | 54 | 88 | 87 | – | – | 40 |
| Innsbruck | 53 | 36 | 66 | 66 | – | 4 (11/26) | 29 |
| Bregenz | 52 | 46 | 45 | 46 | 47 | 1 (11/26) | 12 (20/26) |
| Bozen | – | 75 | 60 | 43 | – | 0 (11/26) | 49 |
| Brixen | – | 54 | 48 | 45 | – | 0 (11/26) | 56 |
| Chur | – | 21 | 22 | – | 22 | 0 (11/26) | 13 (20/26) |
| Luzern | – | 34 | – | – | 42 | 0 (11/26) | 14 (20/26) |
| Davos | – | 31 | 47 | – | 39 | 0 (11/26) | 26 |

**7, 14 und 30 Tage bis 2026-09-29, wie angefragt:**

| Ort | Fenster | Radar DWD | Modell | INCA | SPARTACUS | RprelimD | CombiPrecip | DPC |
|---|---|---|---|---|---|---|---|---|
| Salzburg | 7 T | 5 | 6 | 4 | 6 | – | – | – |
|  | 14 T | 51 | 28 | 43 | 47 | – | – | – |
|  | 30 T | 95 (26/30) | 68 (27/30) | 81 | 82 | – | – | – |
| Kufstein | 7 T | 12 | 7 | 14 | 12 | – | 4 | 4 |
|  | 14 T | 47 | 42 | 49 | 46 | – | 4 (11/14) | 8 |
|  | 30 T | 88 (26/30) | 93 (27/30) | 90 | 87 | – | 4 (11/30) | 9 (29/30) |
| Gmunden | 7 T | 4 | 4 | 21 | 7 | – | – | – |
|  | 14 T | 58 | 30 | 80 | 49 | – | – | – |
|  | 30 T | 113 (26/30) | 67 (27/30) | 128 | 93 | – | – | – |
| Zell am See | 7 T | 11 | 11 | 19 | 18 | – | – | 5 |
|  | 14 T | 28 | 26 | 46 | 42 | – | – | 15 |
|  | 30 T | 53 (26/30) | 54 (27/30) | 113 | 116 | – | – | 48 |
| Innsbruck | 7 T | 2 | 4 | 4 | 3 | – | 4 | 11 |
|  | 14 T | 21 | 20 | 32 | 31 | – | 4 (11/14) | 19 |
|  | 30 T | 53 (26/30) | 36 (27/30) | 75 | 73 | – | 4 (11/30) | 31 |
| Bregenz | 7 T | 0 | 0 | 0 | 0 | 0 | 1 | 1 |
|  | 14 T | 8 | 12 | 7 | 8 | 9 | 1 (11/14) | 6 |
|  | 30 T | 52 (26/30) | 46 (27/30) | 46 | 46 | 47 | 1 (11/30) | 12 (20/30) |
| Bozen | 7 T | – | 0 | 0 | 0 | – | 0 | 0 |
|  | 14 T | – | 11 | 11 | 8 | – | 0 (11/14) | 11 |
|  | 30 T | – | 75 (27/30) | 60 | 45 | – | 0 (11/30) | 50 |
| Brixen | 7 T | – | 0 | 0 | 0 | – | 0 | 0 |
|  | 14 T | – | 11 | 9 | 7 | – | 0 (11/14) | 9 |
|  | 30 T | – | 54 (27/30) | 142 | 103 | – | 0 (11/30) | 126 |
| Chur | 7 T | – | 0 | 0 | – | 0 | 0 | 0 |
|  | 14 T | – | 10 | 8 | – | 9 | 0 (11/14) | 12 |
|  | 30 T | – | 21 (27/30) | 22 | – | 23 | 0 (11/30) | 13 (20/30) |
| Luzern | 7 T | – | 0 | – | – | 0 | 0 | 0 |
|  | 14 T | – | 7 | – | – | 11 | 0 (11/14) | 9 |
|  | 30 T | – | 34 (27/30) | – | – | 42 | 0 (11/30) | 14 (21/30) |
| Davos | 7 T | – | 0 | 0 | – | 0 | 0 | 0 |
|  | 14 T | – | 5 | 15 | – | 13 | 0 (11/14) | 16 |
|  | 30 T | – | 31 (27/30) | 52 | – | 42 | 0 (11/30) | 28 |

Lesehilfen:

- **Salzburg** bestätigt die Ausgangsbeobachtung: 14 Tage Modell 28 mm,
  gemessen 43 (INCA) bzw. 47 (SPARTACUS), Radar 51.
- **Zell am See und Innsbruck** zeigen das Radar in den inneralpinen
  Tälern: 53 mm gegen 87–88 bzw. 53 gegen 66 über 26 Tage. Abschattung
  durch die Kalkalpen, und kein Regenmesser zum Angleichen.
- **Brixen, 30 Tage:** Modell 54 gegen 103–142 — fast alles davon fiel
  am 08-31 und 09-01 (INCA 52 + 41 mm), also an den Tagen, die im
  Modellstapel fehlen. Über 26 Tage liegen alle bei 45–56.
- **Bozen:** Das Modell liegt dort zu hoch (75 gegen 43–60).
- **CombiPrecip** hat nur 11 vollständige Tage (09-19 bis 09-29), und in
  die fiel fast kein Regen. Die Nullen sagen nichts über die Güte.
- **DPC** außerhalb Italiens (Kufstein 9, Innsbruck 29, Luzern 14)
  nicht verwenden.

## Der Flächenvergleich (26 Tage, 09-04 bis 09-29)

Abdeckung: Rasterpunkte mit allen 26 Tagen.

| Quelle | AT (1 436) | CH+LI (706) | IT-Box (690) | sonstige (728) |
|---|---|---|---|---|
| DWD-Radar | 324 | 155 | 0 | 52 |
| Modell | 1 436 | 706 | 690 | 728 |
| INCA | 1 436 | 310 | 445 | 477 |
| SPARTACUS | 1 335 | 40 | 98 | 10 |
| RprelimD | 48 | 685 | 50 | 37 |
| DPC | 609 | 278 | 690 | 221 |

Übereinstimmung der 26-Tage-Summen: Median des Verhältnisses A/B,
Pearson-r, Median der absoluten Differenz.

| Land | A gegen B | Punkte | A/B | r | Abw. (mm) |
|---|---|---|---|---|---|
| AT | SPARTACUS / INCA | 1 335 | 1,02 | 0,91 | 6,3 |
| AT | Modell / INCA | 1 436 | 0,80 | 0,82 | 13,1 |
| AT | Modell / SPARTACUS | 1 335 | 0,79 | 0,76 | 14,7 |
| AT | DWD-Radar / INCA | 324 | 0,85 | 0,58 | 15,7 |
| AT | DWD-Radar / SPARTACUS | 318 | 0,81 | 0,52 | 19,0 |
| AT | RprelimD / INCA | 48 | 0,97 | 0,51 | 4,9 |
| AT | DPC / INCA | 609 | 0,38 | 0,43 | 46,0 |
| CH | RprelimD / INCA | 307 | 0,92 | 0,69 | 6,5 |
| CH | Modell / RprelimD | 685 | 1,02 | 0,74 | 8,4 |
| CH | DWD-Radar / RprelimD | 148 | 1,03 | 0,82 | – |
| CH | SPARTACUS / RprelimD | 38 | 0,94 | 0,73 | 6,5 |
| CH | DPC / RprelimD | 270 | 0,44 | 0,75 | 19,2 |
| IT | DPC / SPARTACUS | 98 | 0,98 | 0,57 | 10,0 |
| IT | DPC / RprelimD | 50 | 1,06 | 0,83 | 9,3 |
| IT | DPC / INCA | 445 | 1,08 | 0,44 | 22,1 |
| IT | Modell / DPC | 690 | 0,94 | 0,71 | 19,8 |
| IT | RprelimD / INCA | 22 | 2,61 | 0,32 | 40,4 |

Gegenprobe in **Bayern** (389 Punkte südlich 48,6° N, wo RADOLAN mit
Stationen angeeicht ist): DWD-Radar / INCA = **1,00, r 0,90**, Abw.
5,0 mm (Alpenrand 0,94 / r 0,78, Vorland 1,02 / r 0,90). INCA schließt
also nahtlos an das Radar an; die Schwäche des Radars in Österreich ist
eine des Radars jenseits seines Netzes, nicht eine von INCA.

Abfall des DWD-Radars mit dem Abstand zur deutschen Grenze (Österreich,
Abstand grob über die Breite):

| Abstand | Punkte | Radar / INCA | r | Modell / INCA |
|---|---|---|---|---|
| 0–25 km | 109 | 0,92 | 0,76 | 0,80 |
| 25–50 km | 90 | 0,75 | 0,71 | 0,72 |
| 50–80 km | 37 | 1,07 | −0,29 | 0,76 |
| > 80 km | 62 | 0,62 | 0,56 | 0,72 |

### Stimmen die gemessenen Quellen an den Grenzen überein?

- **AT/DE:** INCA gegen RADOLAN in Bayern 1,00 / r 0,90 — ja. In
  Österreich gegen das DWD-Radar nur 0,85 / r 0,58; das liegt am Radar.
- **CH/AT:** RprelimD gegen INCA im österreichischen Saum 0,97, gegen
  SPARTACUS in der Schweiz 0,94 / r 0,73, in Bregenz 47 / 45 / 46 mm —
  ja, im Rahmen der 06–06-Verschiebung.
- **IT/AT:** DPC gegen SPARTACUS in Südtirol 0,98 / r 0,57, Brixen
  56 / 45 mm, Bozen 49 / 43 — ja im Mittel, mit Streuung je Ort.
  DPC gegen INCA in Italien 1,08 / r 0,44: INCA wird südlich des
  Alpenhauptkamms schwächer.
- **IT/CH:** DPC gegen RprelimD im Tessin-Saum 1,06 / r 0,83 — ja.
- **Nicht** über die Grenze tragen: DPC (in AT 0,38, in CH 0,44),
  RprelimD in Italien gegen INCA (2,61), CombiPrecip außerhalb der
  Schweiz. Jede Quelle gehört in ihr eigenes Land.

## Empfehlung

**Entschieden** (Betreiber, 2026-10-01): Einbau nach dieser Empfehlung,
einschließlich der geänderten Reihenfolge; die Wahl der Landesgrenzen
liegt beim Einbau (siehe unten).

**Reihenfolge je Tag und Punkt:**

1. **Nationale Messung, nur im eigenen Land:**
   Österreich → INCA; Schweiz und Liechtenstein → RprelimD;
   Italien → DPC Merging.
2. **DWD-Radar** — in Deutschland ohnehin, außerhalb nur noch dort, wo
   kein nationales Gitter gilt.
3. **Modell** — Slowenien, Tschechien, Slowakei, Ungarn, Frankreich und
   jede Lücke.

Damit ersetzt die Messung das Modell in Österreich, der Schweiz, in
Liechtenstein und in der italienischen Alpenbox vollständig für die
Vergangenheit. Das Modell bleibt Rückfall und deckt den Rest der Box.

**Warum nicht SPARTACUS für Österreich, obwohl es reine Messung ist:**
Beide stimmen überein (r 0,91). INCA hat aber UTC-Tage wie der
Radarstapel (keine Naht an der Grenze nach Bayern), die österreichischen
Radare, die in keinem anderen freien Produkt stecken, und deckt ganz
Österreich lückenlos (1 436 gegen 1 335 Punkte). SPARTACUS wird der
Prüfstein im Workflow — ein unabhängiges zweites Instrument für
dasselbe Land ist genau das, was dem Radarstapel mit `--verify` gegen
`GetFeatureInfo` fehlt.

**Warum „nur im eigenen Land“:** Die Gitter reichen alle über die
Grenzen, und jenseits davon taugen sie wenig (Tabelle oben). Ohne eine
Länderzuordnung würde in Italien INCA vor DPC gewinnen oder in Österreich
DPC einspringen. Die Zuordnung gehört in den CI-Bau, nicht in die App:
Jede Quelle wird vor dem Kodieren auf ihr Land beschnitten, die Stapel
sind dann disjunkt, und die App braucht keine Länder zu kennen.

**Landesgrenzen: Natural Earth 1:10m, Admin-0.** Public Domain, also
keine weitere Lizenz und keine Namensnennung — OSM-Grenzen wären ODbL
und eine Zeile mehr auf der Lizenzseite, die amtlichen Grenzen (BEV,
swisstopo, ISTAT) drei Quellen mit drei Lizenzen. Die Lagegenauigkeit
von einigen hundert Metern reicht für 1-km-Zellen, und ein Fehler um
eine Zelle kostet nichts: An den Grenzen sind sich die Quellen einig
(Bregenz 45/46/47 mm, Tabelle oben). Die Gültigkeitsmasken der Produkte
taugen nicht, weil jedes Produkt über seine Grenze hinausreicht. Die
Maske wird nur in CI gebraucht, nie in der App: einmal mit der
Standardbibliothek erzeugt (Punkt-in-Polygon auf dem 1-km-Raster),
eingecheckt unter `tool/` mit Prüfsumme, und ein Selbsttest prüft
Grenzorte (Bregenz AT, Vaduz LI, Como IT, Brixen IT, Chur CH,
Konstanz DE). Damit hängt der tägliche Lauf nicht an einem weiteren
Download.

**Temperatur ist nicht Teil dieser Empfehlung**, aber dieselben Dienste
liefern sie: INCA `T2M` stündlich, MeteoSchweiz `TmaxD`/`TminD` in
derselben Collection. Das wäre ein eigenes Issue nach diesem.

## Was der Einbau braucht

- **Größe:** Ein Tagesgitter für die ganze Box bei 1 km in Mercator
  (1 258 × 576, Zeilen-Delta + gzip wie der Radarstapel) sind gemessen
  2,2 KB an einem trockenen Tag (09-28) und 60–78 KB an nassen Tagen
  (09-16, 09-10). 26 Tage also rund 1 MB — weniger als der Radarstapel.
- **Lesen in CI:** INCA, SPARTACUS und RprelimD sind NetCDF4 (HDF5),
  DPC GeoTIFF mit deflate. Die Standardbibliothek liest beides nicht.
  `gdalwarp` kann alle drei direkt auf EPSG:3857 bringen und als
  unkomprimiertes GeoTIFF schreiben, das der vorhandene Leser in
  `tool/rain_grid.py` schon versteht — das ist Umprojizieren und
  Zusammensetzen, also die erlaubte GDAL-Rolle. GeoJSON von GeoSphere
  wäre stdlib-lesbar, aber 38 MB je Tag.
- **Abrufe je Lauf:** INCA 1 (je Tag), RprelimD 2, DPC 2 —
  Nachfüllen von 26 Tagen ≈ 130 Anfragen, alle unter den gemessenen
  Grenzen. Keine Nutzerkoordinate, nur feste Boxen.
- **Datenschutz:** Die neuen Hosts (`dataset.api.hub.geosphere.at`,
  `data.geo.admin.ch`, `radar-api.protezionecivile.it`) fragt nur CI.
  Die App lädt weiter nur vom Spiegel. In `lib/` stehen sie höchstens
  als Quellenangabe — `textOnly` im Datenschutz-Wächter.

## Lizenzpflichten

| Quelle | Lizenz | Pflicht |
|---|---|---|
| GeoSphere INCA, SPARTACUS | CC BY 4.0 | Urheber „GeoSphere Austria“, Datensatz mit DOI (INCA https://doi.org/10.60669/6akt-5p05, SPARTACUS https://doi.org/10.60669/5cqg-p427), Lizenzlink, Hinweis auf Änderung („zu Tagessummen addiert, auf 1 mm gerundet, umprojiziert“). |
| MeteoSchweiz RprelimD | CC BY 4.0 | „Meteorological and climatological data provided by MeteoSwiss may only be reproduced and redistributed if the source is acknowledged (Quelle: MeteoSchweiz; …)“ — also **„Quelle: MeteoSchweiz“**. Außerdem: „you must ensure that it does not appear as if MeteoSwiss supports you or your use in particular.“ (https://opendatadocs.meteoswiss.ch/general/terms-of-use) |
| DPC Merging | **CC BY-SA** | Quelle **„Radar-DPC“**; abgeleitete Werke unter derselben Lizenz. Deshalb **eigene Dateien** (`it_rain_*`) mit eigener Quellenangabe, nie mit INCA- oder MeteoSchweiz-Werten in einer Datei vermischt — sonst stünde die gemischte Datei unter BY-SA. Das ist ein weiterer Grund für einen Stapel je Quelle. |
| EUMETNET OPERA (falls je) | CC BY 4.0 | „EUMETNET OPERA“, Lizenzlink |
| E-OBS | NC | nicht verwendbar |

## Offen

- **OPERA:** gemessen und ausgeschlossen (siehe Quellentabelle).
  Nördlich des Alpenhauptkamms brauchbar, dort deckt INCA aber besser;
  südlich und im Schweizer Inneren viel zu trocken, dazu Störechos.
  Neu prüfen erst, wenn GeoSphere oder DPC ihre Radare einspeisen.
- **DPC-Historie:** ab 2026-05-15 — fester Beginn oder rollierend?
  Nachmessen Mitte November. Für den Betrieb egal, der Stapel hält seine
  Tage selbst.
- **RprelimD gegen RhiresD:** Wie stark die endgültigen Werte von den
  vorläufigen abweichen, ist ungemessen. Für 26 Tage Rückblick reicht
  das vorläufige Gitter; ein Nachtausch wäre ein späteres Thema.
- **Länderzuordnung:** entschieden — Natural Earth 1:10m (siehe
  Empfehlung).
- **Regionaldienste Italiens:** Lizenzen von ARPA Lombardia, FVG,
  Piemonte und Aostatal nicht geprüft — nicht nötig, solange DPC trägt.

## Anhang: Entwurf für das Einbau-Issue

> **feat(rain): measured daily precipitation for Austria, Switzerland
> and northern Italy instead of model values (#612 follow-up)**
>
> **Why.** Outside Germany the rain stack is model-only (Open-Meteo
> ICON-D2, 12 km). Measured on 2026-10-01 over 26 days and 3 574 grid
> points (`docs/regendaten-alpenraum.md`): the model is ~20 % low in
> Austria (model/INCA median 0.80), and the DWD radar beyond the German
> border reads 0.85 of INCA with r 0.58, while in Bavaria radar and
> INCA agree (1.00, r 0.90).
>
> **What.**
> - New tool `tool/national_rain.py` (stdlib; GDAL only for `gdalwarp`
>   to EPSG:3857), run in `rain-data.yml` after `daily` and before
>   `model`. One stack per source, each clipped to its home country
>   before encoding:
>   - `at_rain_*` — GeoSphere INCA `inca-v1-1h-1km`, hourly `RR` summed
>     to UTC days, one request per day (10 M data-point limit, 240
>     requests/h).
>   - `ch_rain_*` — MeteoSwiss RprelimD via STAC
>     (`ch.meteoschweiz.ogd-surface-derived-grid`), 06–06 UTC days,
>     published D+1 ~12:17 UTC.
>   - `it_rain_*` — DPC Radar `CUM24` Merging (radar + gauges), CC
>     BY-SA, kept in its own files.
>   - Same encoding as `rain_day_*` (1 mm bytes, row delta, gzip, 255 =
>     no data), new manifest section `national`, 26 days, only missing
>     days fetched, own cleanup list.
> - `--verify`: INCA 26-day sums at random points against SPARTACUS v3
>   (`spartacus-v3-1d-1km`); fail on systematic deviation. RprelimD and
>   DPC: spot checks of single days against a second download.
> - Country mask for the clipping: Natural Earth 1:10m admin-0 (public
>   domain), rasterised once with the stdlib (point-in-polygon on the
>   1 km Mercator grid) and committed under `tool/` with a checksum;
>   self-test on border towns (Bregenz AT, Vaduz LI, Como IT, Brixen IT,
>   Chur CH, Konstanz DE). Not shipped in the app.
> - App: precedence per day and point becomes **national (home country)
>   > DWD radar > model** in `rainCoursesFromStacks` and `AmpelLevels`.
>   `RainDay.source` gains the national sources; the sheet names them
>   („gemessen, GeoSphere Austria“ …).
> - Privacy guard: new hosts are CI-only; attribution strings in `lib/`
>   as `textOnly`. No change to the privacy policy (no new app network
>   target), but `docs/datenschutz-nachweise.md` notes the CI sources.
> - Licence page: GeoSphere Austria (CC BY 4.0, DOIs), „Quelle:
>   MeteoSchweiz“ (CC BY 4.0, no endorsement), „Radar-DPC“ (CC BY-SA
>   4.0, separate files).
>
> **Not in scope.** Temperature from INCA/MeteoSwiss (separate issue),
> OPERA (no Austrian or Italian radars in the composite), regional
> Italian station services.
>
> **Tests.** Self-test with fake services (STAC item, GeoSphere 400 on
> oversized slices, DPC presigned-URL flow); Dart: precedence with three
> stacks, sheet wording per source, licence page entries.
