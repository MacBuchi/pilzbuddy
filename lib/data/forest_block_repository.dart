// Holt die feinen Wald-Blöcke (#253) vom Release `forest-data` und legt
// sie auf Platte. Muster wie `rain_grid_repository.dart`: laden,
// speichern, **still degradieren** — kommt nichts an, bleibt das
// eingebaute 250-m-Asset die Karte, und im Wald ohne Empfang darf eine
// Zugabe nichts kaputt machen.
//
// Kein neues Netzziel: GitHub-Releases stehen seit den Offline-Karten in
// der Datenschutzerklärung.
//
// Anders als beim Regen wird jeder Block gegen die **Prüfsumme aus dem
// Katalog** verifiziert — vor dem Schreiben UND bei jedem Lesen von
// Platte: Der Tag wird quartalsweise überschrieben, und eine Datei vom
// alten Stand unter neuem Katalog wäre sonst ein stiller Versatz von
// Blockmaßen und Gitterwerten. Die Prüfsumme ist damit zugleich die
// Invalidierung — ein Stempel im Dateinamen ist nicht nötig.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../features/map/forest_blocks.dart';
import '../features/map/forest_grid.dart';

/// Woher die Blöcke kommen. Fester Tag, keine Version — die Daten ändern
/// sich quartalsweise, die App nicht (dasselbe Muster wie `rain-data`).
const forestDataBaseUrl =
    'https://github.com/MacBuchi/pilzbuddy/releases/download/forest-data';

/// Ein Block kam nicht durch: kein Netz, kein 200 oder eine Prüfsumme,
/// die nicht passt.
///
/// Nur der **Vorlauf** (#264) kennt diesen Fehler. Der Weg auf Bedarf
/// bleibt still bei `null` — dort ist ein fehlender Block eine Lücke, die
/// das Asset füllt. Wer dagegen „alles herunterladen" tippt, hat genau
/// das Gegenteil verlangt und muss erfahren, dass es nicht geklappt hat.
class ForestBlockDownloadFailed implements Exception {
  const ForestBlockDownloadFailed(this.file);

  final String file;

  @override
  String toString() => 'Waldblock $file ließ sich nicht laden';
}

/// Was von einem Katalog auf dem Gerät liegt.
typedef ForestBlocksOnDisk = ({int blocks, int bytes});

class ForestBlockRepository {
  ForestBlockRepository({http.Client? client, Directory? baseDirOverride})
      : _client = client ?? http.Client(),
        _baseDirOverride = baseDirOverride;

  final http.Client _client;
  final Directory? _baseDirOverride;

  /// Dekodierte Blöcke im Speicher, Schlüssel Datei+Prüfsumme (ein
  /// Katalog-Update wechselt die Prüfsumme und läuft so automatisch am
  /// alten Eintrag vorbei). Klein gedeckelt: Ein Block sind ~3 MB roh,
  /// und diese App ist schon einmal an Speicherdruck gestorben
  /// (#142/#151).
  final _decoded = <String, ForestGrid>{};
  static const _decodedCap = 8;

  Future<Directory> _dir() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/forest');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Der Katalog — frisch vom Netz, sonst der letzte von Platte, sonst
  /// `null`. Ein frischer Katalog räumt zugleich Blöcke weg, die er
  /// nicht mehr führt (umgeschnittene Blöcke hießen sonst für immer
  /// Platz).
  Future<ForestBlockCatalog?> loadCatalog() async {
    String? raw;
    try {
      final response = await _client
          .get(Uri.parse('$forestDataBaseUrl/forest_blocks.json'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) raw = response.body;
    } catch (_) {
      // Still: kein Empfang oder GitHub weg — unten liegt vielleicht
      // noch ein Stand auf Platte. Kein `logError`; ein Abruf im Wald
      // ohne Netz ist ein normaler Vorgang (#124/#136).
    }

    if (raw != null) {
      final catalog = _parse(raw);
      if (catalog != null) {
        try {
          final dir = await _dir();
          await File('${dir.path}/blocks.json').writeAsString(raw, flush: true);
          await _prune(dir, catalog);
        } catch (_) {
          // Ohne gemerkten Katalog fehlt nur der Weg ohne Empfang.
        }
        return catalog;
      }
    }

    try {
      final file = File('${(await _dir()).path}/blocks.json');
      if (!await file.exists()) return null;
      return _parse(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  ForestBlockCatalog? _parse(String raw) {
    try {
      return ForestBlockCatalog.tryParse(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Blockdateien wegräumen, die der Katalog nicht mehr führt. Die
  /// Prüfung läuft über den Dateinamen; veraltete INHALTE unter
  /// gültigem Namen fallen beim Lesen durch die Prüfsumme.
  Future<void> _prune(Directory dir, ForestBlockCatalog catalog) async {
    try {
      final keep = {for (final block in catalog.blocks) block.file};
      for (final entry in dir.listSync().whereType<File>()) {
        final name = entry.path.split('/').last;
        if (!name.startsWith('forest_block_')) continue;
        if (keep.contains(name)) continue;
        await entry.delete();
      }
    } catch (_) {
      // Aufräumen ist Kür.
    }
  }

  /// Ein Block als ausgepacktes Gitter — aus dem Speicher, von Platte
  /// oder vom Netz; `null`, wenn nichts davon trägt. Jeder Weg endet an
  /// derselben Prüfsummen-Kontrolle.
  Future<ForestGrid?> loadBlock(
      ForestBlockCatalog catalog, ForestBlockInfo info) async {
    final key = '${info.file}:${info.sha256}';
    final cached = _decoded.remove(key);
    if (cached != null) {
      _decoded[key] = cached; // ans Ende — zuletzt benutzt lebt länger
      return cached;
    }

    final file = File('${(await _dir()).path}/${info.file}');
    var bytes = await _readVerified(file, info);
    if (bytes == null) {
      bytes = await _downloadVerified(info);
      if (bytes == null) return null;
      try {
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // Kein Platz, kein Schreibrecht: Der Block trägt trotzdem für
        // diesen Lauf — beim nächsten wird eben neu geladen.
      }
    }

    final grid = await compute(_decode, (
      bytes: bytes,
      width: info.width,
      height: info.height,
      west: info.west,
      east: info.east,
      north: info.north,
      south: info.south,
      referenceYear: catalog.referenceYear,
      hexLonStep: catalog.hexLonStep,
      hexLatStep: catalog.hexLatStep,
    ));
    if (grid == null) {
      // Prüfsumme stimmte, Auspacken scheiterte trotzdem: Dann ist der
      // KATALOG kaputt (falsche Maße) — die Datei kann bleiben, aber
      // liefern dürfen wir nichts.
      return null;
    }
    _decoded[key] = grid;
    if (_decoded.length > _decodedCap) {
      _decoded.remove(_decoded.keys.first);
    }
    return grid;
  }

  /// Wie viel des Katalogs schon auf Platte liegt (#264) — die Grundlage
  /// der Kachel „18 von 30 Blöcken · 15 MB".
  ///
  /// Zählt über Dateigröße, nicht über die Prüfsumme: Die volle Prüfung
  /// wären 26 MB SHA-256 bei jedem Aufbau des Bildschirms. Eine Datei mit
  /// richtiger Größe und falschem Inhalt zählt hier also mit — sie fliegt
  /// beim Lesen durch [_readVerified] auf und wird dann neu geholt. Die
  /// Anzeige ist eine Auskunft, keine Garantie; die Garantie gibt die
  /// Prüfsumme an der Stelle, an der die Daten wirklich benutzt werden.
  Future<ForestBlocksOnDisk> installedOf(ForestBlockCatalog catalog) async {
    try {
      final dir = await _dir();
      var blocks = 0;
      var bytes = 0;
      for (final block in catalog.blocks) {
        if (await _present(File('${dir.path}/${block.file}'), block)) {
          blocks++;
          bytes += block.bytes;
        }
      }
      return (blocks: blocks, bytes: bytes);
    } catch (_) {
      // Kein Verzeichnis, kein Leserecht: Dann liegt eben nichts da.
      return (blocks: 0, bytes: 0);
    }
  }

  /// Holt alle noch fehlenden Blöcke des Katalogs und meldet den
  /// Fortschritt über den GANZEN Katalog (0..1).
  ///
  /// Über den ganzen und nicht über die fehlenden: Wer einen
  /// abgebrochenen Vorlauf fortsetzt, soll den Balken dort weiterlaufen
  /// sehen, wo er stand — nicht wieder bei null.
  ///
  /// Der Fortschritt zählt in **Bytes**, nicht in Blöcken: zwischen dem
  /// kleinsten (0,07 MB) und dem größten (1,4 MB) liegt Faktor 20, eine
  /// Blockzählung liefe also sichtbar ungleichmäßig.
  ///
  /// Fehlschläge werden geworfen ([ForestBlockDownloadFailed]) — der
  /// Vorlauf-Notifier wartet daraufhin auf die Verbindung und setzt fort;
  /// was schon liegt, wird beim nächsten Anlauf übersprungen.
  Stream<double> downloadAll(
    ForestBlockCatalog catalog, {
    bool Function()? isCancelled,
  }) async* {
    final cancelled = isCancelled ?? () => false;
    final total = catalog.blocks.fold<int>(0, (sum, b) => sum + b.bytes);
    if (total <= 0) return;

    final dir = await _dir();
    var done = 0;
    final missing = <ForestBlockInfo>[];
    for (final block in catalog.blocks) {
      if (await _present(File('${dir.path}/${block.file}'), block)) {
        done += block.bytes;
      } else {
        missing.add(block);
      }
    }
    yield done / total;

    for (final block in missing) {
      if (cancelled()) return;
      final bytes = await _downloadVerified(block);
      if (bytes == null) throw ForestBlockDownloadFailed(block.file);
      // Ein Schreibfehler wird hier bewusst NICHT geschluckt (anders als
      // in [loadBlock], wo der Block für den laufenden Lauf trotzdem
      // trägt): Beim Vorlauf ist das Speichern der ganze Zweck.
      await File('${dir.path}/${block.file}').writeAsBytes(bytes, flush: true);
      done += block.bytes;
      yield done / total;
    }
  }

  /// Wirft die feinen Blöcke vom Gerät und liefert, wie viel frei wurde.
  ///
  /// Der Katalog-Cache (`blocks.json`) bleibt liegen: Er ist winzig und
  /// hält die Kachel auch ohne Empfang aussagefähig.
  Future<int> deleteBlocks() async {
    var freed = 0;
    try {
      final dir = await _dir();
      for (final entry in dir.listSync().whereType<File>()) {
        if (!entry.path.split('/').last.startsWith('forest_block_')) continue;
        freed += await entry.length();
        await entry.delete();
      }
    } catch (_) {
      // Was sich nicht löschen lässt, bleibt liegen — der Zähler nennt
      // dann eben weniger. Kein Grund für eine Fehlermeldung.
    }
    // Sonst zeigte die Karte die eben gelöschten Blöcke aus dem Speicher
    // weiter, bis die App neu startet.
    _decoded.clear();
    return freed;
  }

  /// Liegt der Block in erwarteter Größe da? Siehe [installedOf] für den
  /// Grund, warum hier nicht die Prüfsumme zählt.
  Future<bool> _present(File file, ForestBlockInfo info) async {
    try {
      return await file.exists() && await file.length() == info.bytes;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>?> _readVerified(File file, ForestBlockInfo info) async {
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (_verified(bytes, info)) return bytes;
      // Alter Stand unter neuem Katalog (der Tag wird überschrieben):
      // weg damit, sonst vergiftet er jeden weiteren Versuch.
      await file.delete();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>?> _downloadVerified(ForestBlockInfo info) async {
    try {
      final response = await _client
          .get(Uri.parse('$forestDataBaseUrl/${info.file}'))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      return _verified(bytes, info) ? bytes : null;
    } catch (_) {
      // Still, wie beim Regen: Die feine Stufe ist eine Zugabe.
      return null;
    }
  }

  bool _verified(List<int> bytes, ForestBlockInfo info) =>
      bytes.length == info.bytes &&
      sha256.convert(bytes).toString() == info.sha256;
}

ForestGrid? _decode(
    ({
      List<int> bytes,
      int width,
      int height,
      double west,
      double east,
      double north,
      double south,
      int referenceYear,
      double hexLonStep,
      double hexLatStep,
    }) input) {
  try {
    return ForestGrid.decode(
      input.bytes,
      width: input.width,
      height: input.height,
      west: input.west,
      east: input.east,
      north: input.north,
      south: input.south,
      referenceYear: input.referenceYear,
      hexLonStep: input.hexLonStep,
      hexLatStep: input.hexLatStep,
    );
  } catch (_) {
    return null;
  }
}
