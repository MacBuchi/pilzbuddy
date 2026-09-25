// Nichts Privates im öffentlichen Repo (Betreiber, 2026-09-25: „dafür
// haben wir den DocuHub").
//
// Anlass: `AGENTS.md` war seit #485 nicht mehr nachgezogen worden und
// nannte weiter den Schlüsselordner und das Play-Testkonto, lange nachdem
// CLAUDE.md beides ersetzt hatte. Eine zweite Kopie derselben Regeln
// veraltet still, und mit ihr das, was nicht mehr darin stehen sollte.
//
// Geprüft wird jede EINGECHECKTE Textdatei. Was hier anschlägt, gehört in
// den DocuHub; im Repo bleibt ein Verweis.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _forbidden = <String, RegExp>{
  'absoluter Pfad auf dem Rechner': RegExp(r'/(Users|Volumes)/\w'),
  // Zusammengesetzt, sonst träfe das Muster diese Datei selbst.
  'Schlüsselordner': RegExp('pilzbuddy' '-keys'),
  'Sync-Ordner des Betreibers': RegExp('Claude' '_exchange'),
  'private Mailadresse':
      RegExp(r'[\w.+-]+@(web\.de|gmail\.com|gmx\.(de|net)|t-online\.de)'),
};

void main() {
  test('keine privaten Angaben in eingecheckten Dateien', () {
    final files = (Process.runSync('git', ['ls-files']).stdout as String)
        .split('\n')
        .where((f) => f.isNotEmpty)
        .where((f) => !f.endsWith('.lock'))
        .toList();
    expect(files.length, greaterThan(100), reason: 'git ls-files lief nicht');
    final hits = <String>[];
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        continue; // Binärdatei
      }
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final MapEntry(key: what, value: pattern) in _forbidden.entries) {
          if (pattern.hasMatch(lines[i])) hits.add('$path:${i + 1} — $what');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('der Wächter schlägt an', () {
    // Gegenprobe gegen die Muster selbst — ein Muster, das nie trifft,
    // wäre ein grüner Test über nichts. Die Beispiele werden zur Laufzeit
    // zusammengesetzt, sonst fände der Test oben diese Datei selbst.
    const slash = '/';
    expect(_forbidden['absoluter Pfad auf dem Rechner']!
        .hasMatch('${slash}Volumes${slash}MacStore${slash}x'), isTrue);
    expect(_forbidden['absoluter Pfad auf dem Rechner']!
        .hasMatch('/users/api_token'), isFalse, reason: 'iNat-Pfad');
    expect(_forbidden['private Mailadresse']!.hasMatch('jemand' '@' 'web.de'),
        isTrue);
    expect(_forbidden['private Mailadresse']!
        .hasMatch('pilzfreund@example.org'), isFalse);
  });
}
