# Artbilder in hoher Auflösung

Diese Dateien gehören **nicht** ins APK. Die App liefert 400×400 mit;
hier liegen dieselben Bilder in 1200×1200, damit eine formatfüllende
Ansicht scharf ist (PilzBuddy #537).

## Warum ein Branch und kein Release-Anhang

Release-Anhänge gibt GitHub einem Browser nicht heraus: Weder die
Weiterleitung von `github.com` noch das Ziel schicken einen
`access-control-allow-origin`-Header. Dieselbe Wand wie bei den
Regendaten (#365/#366). Ein Branch wird von `raw.githubusercontent.com`
mit `*` ausgeliefert und braucht keinen Workflow.

Der Branch trägt **einen Wurzel-Commit und wird force-gepusht**. Sonst
wüchse die Historie bei jedem ersetzten Bild um dessen volle Größe — und
ersetzt wird hier laufend: Jedes Commons-Bild ist ein Platzhalter, bis
der Betreiber die Art selbst fotografiert.

## Herkunft und Lizenz

Die Dateinamen entsprechen denen in `assets/species/` im Hauptzweig.
Urheber und Lizenz je Bild stehen dort in `lib/core/species_photos.dart`
und in der App auf der Lizenzseite. Eigene Aufnahmen: MacBuchi,
CC BY-SA 4.0. Alles Übrige stammt von Wikimedia Commons unter CC0,
CC BY oder CC BY-SA.

Metadaten tragen die Dateien keine; geprüft wird über die RIFF-Blockliste
und nicht per Textsuche, weil „EXIF" als vier Bytes in Bilddaten
zufällig vorkommt.

Erzeugt von `hires.py`; die Quelldateien liegen beim Betreiber.

## Größe

Ziel sind 1200×1200. Gibt ein Original das nicht her, liegt das Bild in
SEINER Größe hier (Birkenrotkappe 960, Nelkenschwindling 1020,
Semmelstoppelpilz 1060) — hochgerechnet wird nie, das erfände Schärfe.
Unter 800 lohnt es nicht; das Judasohr bleibt deshalb beim 400er.
Gebaut von `python3 tool/species_photos.py --large DIR` im Hauptzweig,
mit demselben Ausschnitt wie das 400er (per SSIM geprüft); ob jedes Bild
eine große Fassung hat, prüft `--check-large` in CI (#588).
