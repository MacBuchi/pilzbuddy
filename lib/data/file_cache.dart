// Ein Verzeichnis mit Größengrenze — für Dateien, die jederzeit neu zu
// holen sind.
//
// Herausgelöst aus `SpeciesPhotoRepository` (#537), als die Fundfotos
// (#532) denselben Speicher brauchten. Zwei Kopien der Aufräumlogik
// wären zwei Stellen, an denen „älteste fliegt zuerst" auseinanderlaufen
// kann.
//
// **Eine Größengrenze, keine Frist** — und das ist der Unterschied zu
// `spot_cache/`, `outbox/` und `tours/`. Deren Inhalt ist entweder eine
// Kopie, die man nicht neu holen kann, oder das Original. Eine Datei
// hier ist beides nicht: Sie ist jederzeit nachladbar, also darf sie
// weg, sobald sie Platz kostet.
//
// **Im Browser speichern wir nichts selbst.** `path_provider` gibt es
// dort nicht, und es braucht auch keinen eigenen Speicher: Der Browser
// hat seinen HTTP-Zwischenspeicher, und der eigene Service Worker legt
// jede erfolgreiche Antwort ohnehin ab (#387). Ein dritter Speicher
// daneben wäre eine dritte Stelle, an der etwas veralten kann.
//
// **Alle Methoden sind total: sie werfen nie.** Was hier liegt, ist
// eine Zugabe — ein Fehler beim Ablegen darf die Ansicht nicht
// mitreißen (CLAUDE.md, „optionale Features dürfen still degradieren").
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';

class BoundedFileCache {
  BoundedFileCache({
    required this.dirName,
    required this.maxBytes,
    this.enabled = !kIsWeb,
    this.baseDirectory,
  });

  /// Unterordner im App-Support-Verzeichnis.
  final String dirName;

  /// Wie viel der Speicher höchstens belegen darf.
  final int maxBytes;

  /// `false` heißt: jedes Mal frisch holen. Im Browser die Vorgabe, im
  /// Test der Weg, ohne Plattform-Kanal auszukommen.
  final bool enabled;

  /// Statt des App-Support-Verzeichnisses — für Tests, die echte Dateien
  /// brauchen (`path_provider` gibt es auf der Test-VM nicht).
  final Directory? baseDirectory;

  Directory? _dir;

  /// Die Belegung, wie sie das letzte Aufräumen gezählt hat, fortgeschrieben
  /// bei jedem Ablegen. `null` heißt: noch nie gezählt.
  ///
  /// Gezählt wird erst, wenn die Grenze überschritten sein KÖNNTE. Bis
  /// #659 las jedes Ablegen das ganze Verzeichnis samt `stat` je Datei —
  /// bei Bildern unerheblich, bei über tausend Kartenkacheln und Dutzenden
  /// Ablagen je Schwenk Arbeit im Main-Isolate, die niemand braucht.
  /// Eine Datei, die jemand anderes entfernt, macht die Zahl zu hoch; das
  /// kostet höchstens ein Aufräumen zu früh, und das zählt neu.
  int? _total;

  /// Dateiname zu einem Schlüssel. Schrägstriche werden Unterstriche:
  /// Ein Schlüssel wie `<uid>/<id>.jpg` soll keinen Unterordner anlegen,
  /// den das Aufräumen dann nicht sieht.
  static String fileNameFor(String key) => key.replaceAll('/', '_');

  Future<Directory?> _cacheDir() async {
    if (!enabled) return null;
    if (_dir != null) return _dir;
    try {
      final base = baseDirectory ?? await getApplicationSupportDirectory();
      _dir = Directory('${base.path}/$dirName');
      await _dir!.create(recursive: true);
      return _dir;
    } catch (e, s) {
      // Kein Verzeichnis heißt: jedes Mal frisch holen. Unschön, aber
      // kein Grund, die Ansicht scheitern zu lassen.
      logError('Bildspeicher anlegen', e, s);
      return null;
    }
  }

  /// Was unter [key] liegt — `null`, wenn nichts.
  Future<Uint8List?> read(String key) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/${fileNameFor(key)}');
      if (!await file.exists()) return null;
      // Beim Lesen die Zeit anfassen: Danach entscheidet das Aufräumen,
      // was am längsten nicht gesehen wurde.
      final bytes = await file.readAsBytes();
      _unawaited(file.setLastAccessed(DateTime.now()));
      return bytes;
    } catch (e, s) {
      logError('Bild aus dem Speicher lesen', e, s);
      return null;
    }
  }

  /// Legt [bytes] unter [key] ab und räumt danach auf.
  ///
  /// **Erst schreiben, dann aufräumen.** Andersherum könnte das gerade
  /// geholte Bild dem Aufräumen zum Opfer fallen.
  Future<void> write(String key, Uint8List bytes) async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      final file = File('${dir.path}/${fileNameFor(key)}');
      final replaced = _total != null && await file.exists()
          ? await file.length()
          : 0;
      // Erst daneben schreiben, dann umbenennen: Ein Abbruch mitten im
      // Schreiben hinterlässt sonst eine halbe Datei, die beim nächsten
      // Lesen als ganze gilt.
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      final known = _total;
      if (known != null) {
        _total = known - replaced + bytes.length;
        if (_total! <= maxBytes) return;
      }
      await _prune(dir);
    } catch (e, s) {
      logError('Bild ablegen', e, s);
    }
  }

  /// Wirft weg, was am längsten nicht angesehen wurde, bis die Grenze
  /// wieder eingehalten ist.
  Future<void> _prune(Directory dir) async {
    try {
      final files = <({File file, int size, DateTime seen})>[];
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final stat = await entry.stat();
        files.add((file: entry, size: stat.size, seen: stat.accessed));
      }
      var total = files.fold<int>(0, (sum, f) => sum + f.size);
      _total = total;
      if (total <= maxBytes) return;
      files.sort((a, b) => a.seen.compareTo(b.seen));
      for (final f in files) {
        if (total <= maxBytes) break;
        await f.file.delete();
        total -= f.size;
        _total = total;
      }
    } catch (e, s) {
      // Ungezählt weiter: Beim nächsten Ablegen wird neu gezählt.
      _total = null;
      logError('Bildspeicher aufräumen', e, s);
    }
  }
}

/// `unawaited` ohne `dart:async` zu importieren — das Anfassen der
/// Zugriffszeit darf das Lesen nicht aufhalten und darf auch scheitern.
void _unawaited(Future<void> future) {
  future.catchError((_) {});
}
