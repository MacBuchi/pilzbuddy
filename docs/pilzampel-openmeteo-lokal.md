# Eigene Open-Meteo-Instanz — und welchen Datensatz wir eigentlich messen

Stand: 2026-09-13 · Issue #460 · betrifft alle Messungen aus
`tool/ampel_validate.py`

Der Anlass war das Kontingent: Eine registrierte Messung dauerte Tage,
weil `archive-api.open-meteo.com` pro Minute, pro Stunde und pro Tag
begrenzt ist. Der Grund, es wirklich zu tun, ist ein anderer.

## Der eigentliche Grund: unsere Messungen pinnen keinen Datensatz

`fetch_weather` fragt die Archiv-API **ohne `models=`**. Damit gilt die
Vorgabe „best match", und was das ist, hat bisher niemand nachgesehen.
Jetzt ist es gemessen — dieselbe Koordinate, dieselben Tage, alle
Datensätze der Reihe nach:

| | 2014-09-01 … 05 | 2020-09-01 … 05 |
|---|---|---|
| **Vorgabe** | T 13.9 13.8 14.4 16.0 17.9 · N 0.0 2.7 0.0 0.0 0.3 | T 14.0 13.8 15.0 18.9 15.9 · N 3.9 0.0 1.4 0.1 2.6 |
| `era5` | T 13.5 14.1 13.9 15.6 17.7 · N **gleich** | T 13.7 13.0 14.4 18.3 15.3 · N 1.2 0.2 4.8 0.7 0.0 |
| `era5_land` | T **gleich wie Vorgabe** · N fehlt | T 14.5 14.0 14.6 18.5 15.9 · N fehlt |
| `ecmwf_ifs` | fehlt | **gleich wie Vorgabe** |

Daraus liest sich die Vorgabe ab, Variable für Variable:

- **Vor 2017:** Temperatur aus ERA5-Land (0,1°), Niederschlag aus ERA5
  (0,25°) — ERA5-Land liefert bei Open-Meteo keinen Niederschlag.
- **Ab 2017:** beides aus IFS HRES (9 km).

**Die Vorgabe wechselt also mitten in unserer Zeitreihe das Instrument.**
Open-Meteos eigene Doku empfiehlt für Klimaanalysen ausdrücklich, ERA5
oder ERA5-Land zu pinnen, „um Artefakte von Modell-Upgrades zu
vermeiden". Genau das haben wir nicht getan.

## Die eigene Instanz ist dasselbe Instrument — gemessen, nicht vermutet

Das ist die Voraussetzung dafür, dass ein Lauf halb aus dem Cache und
halb von dort kommen darf. Verglichen wurden die **gesicherten
Cloud-Antworten im Cache** gegen die lokale Instanz, dieselben Orte,
dieselben Tage (`tool/openmeteo_local_check.py`):

| Art | Jahr | Orte | Abweichung Temperatur | Abweichung Niederschlag |
|---|--:|--:|--:|--:|
| Herbsttrompete | 2014 | 58 | **0,00 K** | **0,00 mm** |
| Herbsttrompete | 2016 | 6 | **0,00 K** | **0,00 mm** |
| Herbsttrompete | 2020 | 6 | **0,00 K** | **0,00 mm** |
| Herbsttrompete | 2022 | 6 | **0,00 K** | **0,00 mm** |

17 644 Tageswerte, keine einzige Abweichung. Mit `models=era5` dagegen:
0,42–0,46 K im Mittel (bis 3,4 K) und ab 2020 1,2–1,3 mm/Tag im Mittel
(bis 30 mm) — der Unterschied ist der Datensatz, nicht der Server.

## Und was ist mit dem berichteten Schwellen-Drift?

`docs/pilzampel-schwellen-messung.md` berichtet: Dieselbe 0,5 wurde vor
2019 an ~30 % der Vergleichstage überschritten, seither an ~20 % — „die
Ampel ist im Feld still pessimistischer geworden". **Der Verdacht war,
dass das der Modellwechsel 2017 ist.** Gemessen (Steinpilz, dieselbe
Ziehung, nur der Datensatz getauscht):

| Jahr | Orte | Vergleichstage ≥ 0,5 (Vorgabe) | mit ERA5 | Ø Regen 26 d (Vorgabe) | ERA5 | Δ |
|---|--:|--:|--:|--:|--:|--:|
| 2013 | 131 | 42,0 % | 42,7 % | 75 mm | 75 mm | +0 |
| 2014 | 180 | 40,2 % | 41,3 % | 78 mm | 78 mm | +0 |
| 2015 | 98 | 12,2 % | 11,2 % | 50 mm | 50 mm | +0 |
| 2016 | 63 | 1,6 % | 1,6 % | 51 mm | 51 mm | +0 |
| 2017 | 119 | 20,2 % | 19,3 % | 72 mm | 66 mm | **+6** |
| 2018 | 49 | 6,1 % | 6,1 % | 33 mm | 31 mm | +1 |
| 2019 | 133 | 19,5 % | 15,8 % | 53 mm | 52 mm | +1 |
| 2020 | 218 | 25,0 % | 20,4 % | 56 mm | 50 mm | **+6** |

**Der Verdacht ist widerlegt — und zwar in die andere Richtung.** Bis
2016 sind die Regensummen identisch (0 mm Unterschied), ab 2017 ist die
Vorgabe **feuchter** als ERA5, und sie zeigt entsprechend **mehr**
günstige Vergleichstage (+0,9 bis +4,6 pp). Der Drift behauptet das
Gegenteil: weniger günstige Tage nach 2019. Das Instrument arbeitet also
GEGEN den berichteten Drift; mit gepinntem Datensatz wäre er eher etwas
größer, nicht kleiner.

Was bleibt: Ab 2017 tragen unsere Zahlen eine Verzerrung von ~+1 bis
+5 pp auf Vergleichstagen, und die liegt quer zur Jahres-Trennlinie jedes
`--fit`-Laufs (Anpassung bis 2018, Prüfung danach). Das ist Grund genug
zu pinnen — aber kein Grund, eine veröffentlichte Zahl zurückzuziehen.

Zwei Vorbehalte dazu, die man mitlesen muss: Gemessen ist EINE Art, und
die Jahresstreuung ist enorm (1,6 % bis 42 %). Die Aussage über die
Richtung des Instrument-Effekts ist gepaart und damit belastbar; die
Aussage über die Größe des Drifts ist es nicht, sie steht in der
Schwellen-Messung.

## Der Aufbau

Der Container liegt **außerhalb des Repos**, neben den anderen
Programmier-Ordnern (Betreiber, 2026-09-13):
`/Volumes/MacStore/Programming/open-meteo/` mit `docker-compose.yml` und
`data/`.

```yaml
services:
  open-meteo:
    image: ghcr.io/open-meteo/open-meteo      # AGPLv3
    container_name: open-meteo
    volumes:
      - ./data:/app/data
    environment:
      REMOTE_DATA_DIRECTORY: https://openmeteo.s3.amazonaws.com/data/
      CACHE_SIZE: 16GB
    ports:
      - '127.0.0.1:8080:8080'                # Messgerät, kein Dienst
    restart: unless-stopped
```

Vier Dinge, die man wissen muss:

- **Kein Voll-Sync nötig.** `REMOTE_DATA_DIRECTORY` lässt den Server die
  `.om`-Dateien stückweise aus dem offenen S3-Bucket lesen und lokal
  zwischenspeichern. Ein Voll-Sync wäre für unsere zwei Variablen
  (`temperature_2m`, `precipitation`, daraus rechnet die API unsere
  Tageswerte) **5,8 GB je Jahr** in ERA5 und ~12,8 GB in ERA5-Land —
  gemessen an den echten Dateigrößen im Bucket, also ~122 bzw. ~270 GB
  für 2006–2026. `sync copernicus_era5 temperature_2m,precipitation
  --year 2006-2026` bleibt der Weg, wenn volle Offline-Reproduzierbarkeit
  gewünscht ist.
- **`data/` enthält EINE vorbelegte `cache.bin`** in Größe `CACHE_SIZE` —
  die 16 GB sind nicht heruntergeladen, sie sind reserviert.
- **Die Daten liegen als Bind-Mount, nicht in einem Docker-Volume.** So
  sind sie auffindbar und beim Aufräumen von Docker nicht weg.
- **Tempo:** 100 Orte × 63 Tage in 99 s (2020, über IFS) bzw. 41 s (2014).
  Ein Art-Jahr ist ein bis zwei solcher Anfragen — eine Art also gut eine
  halbe Stunde, ohne Limit und ohne Wartezyklen. Über die Cloud waren es
  Tage.

## Wie man es benutzt

```
python3 tool/ampel_validate.py --cold \
    --api http://127.0.0.1:8080/v1/archive \
    --cache ~/pilzbuddy-ampel2000/ampel_cache
```

**`--api` ist bewusst nicht die Vorgabe.** Ein Werkzeug, das
stillschweigend mit localhost redet, erzeugt Zahlen, die außerhalb dieses
Rechners niemand nachrechnen kann; der Selbsttest hält die Vorgabe auf
dem öffentlichen Dienst fest.

Und wer die Instanz anfasst — neues Image, anderer Datensatz, `sync`
statt Remote —, führt vorher `tool/openmeteo_local_check.py` aus. Die
Zusage „dasselbe Instrument" ist der Grund, warum Cache und neue Läufe in
einer Tabelle stehen dürfen; sie gilt nur, solange sie gemessen ist.

## Offen

- **`models=` pinnen.** Damit wird der Drift erst deutbar, und die
  Verzerrung quer zur Trennlinie verschwindet. Das ist ein eigener,
  vollständiger Neulauf aller Arten — mit der eigenen Instanz erstmals
  bezahlbar, aber nicht nebenbei zu machen: Der ganze Cache wird dabei
  ungültig.
- **Welcher Datensatz.** ERA5-Land (11 km) ist feiner als ERA5 (25 km),
  liefert bei Open-Meteo aber keinen Niederschlag. Eine Mischung wäre
  wieder zwei Instrumente. Vermutlich ERA5, und die Begründung gehört
  aufgeschrieben.
