// Die Rechnungen des Zeichen-Wegs bleiben ohne Flutter (#689, B2).
//
// Im Browser sollen Wald, Ampel, Fundorte, Höhenlinien, Regenverlauf und
// der Bereichs-Entwurf in einem Web Worker gemalt werden. Der wird als
// eigenes Programm übersetzt (`dart compile js`), und dort gibt es weder
// Flutter noch `dart:ui` — ein einziger Import an der falschen Stelle,
// und der Worker baut nicht mehr. Bis 1.225.0 hingen alle sieben
// Rechnungen über Farben, Konstanten oder Typen an Dateien mit Flutter,
// Riverpod oder `dart:io`; im Diff sieht man so etwas nicht.
//
// Der Test läuft den Importbaum ab den Rechnungen ab, so wie der Browser
// ihn sieht: Bei einem bedingten Import gilt der Zweig für
// `dart.library.js_interop`, sonst der Vorgabe-Zweig (`if (dart.library.io)`
// ist im Browser falsch).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Dateien, deren Funktionen der Zeichen-Weg rechnet.
const _roots = [
  'lib/features/map/forest_fill.dart',
  'lib/features/map/forest_blocks.dart',
  'lib/features/map/gbif_fill.dart',
  'lib/features/map/elevation_contours.dart',
  'lib/features/map/rain_stack.dart',
  'lib/features/offline_areas/area_edit_png.dart',
];

/// Was im Worker nicht übersetzt oder nicht läuft.
final _forbidden = RegExp(r'^(dart:ui|dart:io|dart:isolate|dart:html|'
    r'package:flutter(_\w+)?/|package:riverpod|package:supabase|'
    r'package:path_provider|package:http/|package:pmtiles/)');

final _directive = RegExp(
    r"^\s*(?:import|export)\s+'([^']+)'((?:\s+if\s*\([^)]*\)\s*'[^']+')*)",
    multiLine: true);
final _branch = RegExp(r"if\s*\(\s*dart\.library\.(\w+)\s*\)\s*'([^']+)'");

/// Die Adresse, die der Browser für eine Direktive nimmt.
String browserUri(String plain, String conditions) {
  for (final m in _branch.allMatches(conditions)) {
    if (m.group(1) == 'js_interop') return m.group(2)!;
  }
  return plain;
}

/// Alle verbotenen Importe im Baum ab [roots], je mit der Datei, die ihn
/// zieht.
List<String> forbiddenImports(List<String> roots) {
  final seen = <String>{};
  final queue = [...roots];
  final hits = <String>[];
  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    if (!seen.add(file)) continue;
    final source = File(file).readAsStringSync();
    for (final m in _directive.allMatches(source)) {
      final uri = browserUri(m.group(1)!, m.group(2) ?? '');
      if (_forbidden.hasMatch(uri)) {
        hits.add('$file → $uri');
      } else if (uri.startsWith('package:pilzbuddy/')) {
        queue.add('lib/${uri.substring('package:pilzbuddy/'.length)}');
      } else if (!uri.contains(':')) {
        queue.add(File(file).parent.uri.resolve(uri).path);
      }
    }
  }
  return hits;
}

void main() {
  test('die Rechnungen des Zeichen-Wegs ziehen kein Flutter', () {
    expect(forbiddenImports(_roots), isEmpty,
        reason: 'Der Web Worker (#689, B2) wird ohne Flutter übersetzt — '
            'Typen, Farben, Konstanten in eine reine Datei legen');
  });

  test('der Wächter sieht einen Import über Umwege', () {
    // Ohne diese Probe wäre ein Wächter, der nichts findet, nicht von
    // einem zu unterscheiden, der nichts sucht.
    expect(forbiddenImports(['lib/features/map/forest_data_providers.dart']),
        contains(startsWith('lib/features/map/forest_data_providers.dart → '
            'package:flutter')));
    expect(
        browserUri("'gunzip_web.dart'",
            " if (dart.library.io) 'gunzip_io.dart'"),
        "'gunzip_web.dart'");
    expect(browserUri('a.dart', " if (dart.library.js_interop) 'b.dart'"),
        'b.dart');
  });
}
