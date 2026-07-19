/// Namensschema der Karten-Assets: `<key>_<JJJJMMTT>.pmtiles`,
/// z. B. `de_bayern_20260320.pmtiles` oder `austria_20260320.pmtiles`.
/// Der Katalog entsteht dynamisch aus der Release-Asset-Liste der Quelle —
/// hier stehen nur das Parsing und die deutschen Anzeigenamen.
library;

final _assetPattern = RegExp(r'^(.+)_(\d{8})\.pmtiles$');

/// Bekannte Regionen → Anzeigename. Unbekannte Keys bekommen einen
/// generierten Namen (Wörter groß, Unterstriche zu Leerzeichen), damit
/// neue Regionen der Quelle ohne App-Update auftauchen.
const Map<String, String> kRegionLabels = {
  'de_baden_wuerttemberg': 'Baden-Württemberg',
  'de_bayern': 'Bayern',
  'de_berlin': 'Berlin',
  'de_brandenburg': 'Brandenburg',
  'de_bremen': 'Bremen',
  'de_hamburg': 'Hamburg',
  'de_hessen': 'Hessen',
  'de_mecklenburg_vorpommern': 'Mecklenburg-Vorpommern',
  'de_niedersachsen': 'Niedersachsen',
  'de_nordrhein_westfalen': 'Nordrhein-Westfalen',
  'de_rheinland_pfalz': 'Rheinland-Pfalz',
  'de_saarland': 'Saarland',
  'de_sachsen': 'Sachsen',
  'de_sachsen_anhalt': 'Sachsen-Anhalt',
  'de_schleswig_holstein': 'Schleswig-Holstein',
  'de_thueringen': 'Thüringen',
  'austria': 'Österreich',
  'switzerland': 'Schweiz',
};

/// Zerlegt einen Asset-Dateinamen in (Region-Key, Datumsstempel).
/// Liefert null für Dateien, die nicht zum Schema passen.
({String key, String dateStamp})? parseMapAssetName(String fileName) {
  final match = _assetPattern.firstMatch(fileName);
  if (match == null) return null;
  return (key: match.group(1)!, dateStamp: match.group(2)!);
}

String regionLabel(String key) {
  final known = kRegionLabels[key];
  if (known != null) return known;
  return key
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

/// Deutsche Regionen zuerst (alphabetisch), danach der Rest.
int compareRegionKeys(String a, String b) {
  final aIsGerman = a.startsWith('de_');
  final bIsGerman = b.startsWith('de_');
  if (aIsGerman != bIsGerman) return aIsGerman ? -1 : 1;
  return _sortKey(regionLabel(a)).compareTo(_sortKey(regionLabel(b)));
}

/// Umlaute fürs Sortieren einebnen — sonst landet „Österreich" hinter „Z".
String _sortKey(String label) => label
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');

/// "20260320" → "20.3.2026" für die Anzeige.
String formatDateStamp(String dateStamp) {
  if (dateStamp.length != 8) return dateStamp;
  final day = int.tryParse(dateStamp.substring(6, 8));
  final month = int.tryParse(dateStamp.substring(4, 6));
  final year = dateStamp.substring(0, 4);
  if (day == null || month == null) return dateStamp;
  return '$day.$month.$year';
}
