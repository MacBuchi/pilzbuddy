// Die hochaufgelösten Artbilder (#537) — nachgeladen, nicht mitgeliefert.
//
// Im APK stecken 400x400. Das reicht für die Kacheln im Bildstreifen
// (150 dp mal dreifache Pixeldichte sind 450), formatfüllend wäre es
// sichtbar weich: Ein modernes Telefon will rund 1200. Alle Bilder in
// dieser Größe mitzuliefern hieße 15,9 MB in jeder Installation, für
// eine Ansicht, die die meisten selten öffnen.
//
// **Ein Branch, kein Release-Anhang**, und das ist keine Geschmacksfrage:
// Release-Anhänge gibt GitHub einem Browser nicht heraus — weder die
// Weiterleitung von `github.com` noch das Ziel schicken einen
// `access-control-allow-origin`-Header (#365/#366, gemessen). Ein Branch
// wird von `raw.githubusercontent.com` mit `*` ausgeliefert. Dieselbe
// Entscheidung und derselbe Grund wie beim Regengitter.
//
// **Kein neues Netzziel**: `raw.githubusercontent.com` steht längst in
// der Datenschutzerklärung, weil die Regendaten von dort kommen.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';

/// Wo die großen Fassungen liegen.
///
/// Ein Wurzel-Commit, force gepusht — sonst wüchse die Historie bei
/// jedem ersetzten Bild um dessen volle Größe, und ersetzt wird hier
/// laufend: Jedes Commons-Bild ist ein Platzhalter, bis der Betreiber
/// die Art selbst fotografiert.
const kSpeciesPhotoBaseUrl =
    'https://raw.githubusercontent.com/MacBuchi/pilzbuddy/species-photos';

/// Wie viel der Zwischenspeicher höchstens belegen darf.
///
/// **Eine Größengrenze, keine Frist** — und das ist der Unterschied zu
/// `spot_cache/`, `outbox/` und `tours/`. Deren Inhalt ist entweder eine
/// Kopie, die man nicht neu holen kann, oder das Original. Ein Bild ist
/// beides nicht: Es ist jederzeit nachladbar, also darf es weg, sobald
/// es Platz kostet.
const kSpeciesPhotoCacheBytes = 24 * 1024 * 1024;

/// Holt ein hochaufgelöstes Artbild und hebt es auf.
///
/// **Alle Methoden sind total: sie werfen nie.** Das große Bild ist eine
/// Zugabe — das mitgelieferte 400er steht ohnehin da. Ein Fehler hier
/// darf die Ansicht nicht mitreißen (CLAUDE.md, „optionale Features
/// dürfen still degradieren").
class SpeciesPhotoRepository {
  SpeciesPhotoRepository({
    HttpClient? client,
    this.cachesToDisk = !kIsWeb,
    this.baseUrl = kSpeciesPhotoBaseUrl,
  }) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// **Nur damit der Test ohne Netz auskommt.** Die Projektregel lautet
  /// „kein Netzwerk in Tests"; ohne diesen Haken liefe der Fall „Abruf
  /// scheitert" gegen den echten Dienst und wäre in CI ein Flatterer.
  final String baseUrl;

  /// **Im Browser speichern wir nichts selbst.** `path_provider` gibt es
  /// dort nicht, und es braucht auch keinen eigenen Speicher: Der
  /// Browser hat seinen HTTP-Zwischenspeicher, und der eigene Service
  /// Worker legt jede erfolgreiche Antwort ohnehin ab (#387). Ein
  /// dritter Speicher daneben wäre eine dritte Stelle, an der etwas
  /// veralten kann.
  final bool cachesToDisk;

  Directory? _dir;

  Future<Directory?> _cacheDir() async {
    if (!cachesToDisk) return null;
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      _dir = Directory('${base.path}/species_photos');
      await _dir!.create(recursive: true);
      return _dir;
    } catch (e, s) {
      // Kein Verzeichnis heißt: jedes Mal frisch holen. Unschön, aber
      // kein Grund, die Ansicht scheitern zu lassen.
      logError('Bildspeicher anlegen', e, s);
      return null;
    }
  }

  /// Das große Bild zu einem Asset-Pfad — `null`, wenn es nicht zu
  /// holen war.
  ///
  /// Der Dateiname ist derselbe wie im Asset-Ordner, das ist die ganze
  /// Zuordnung. Eine zweite Tabelle wäre die Stelle, an der ein
  /// getauschtes Bild seinen alten Namen behält.
  Future<Uint8List?> load(String assetPath) async {
    final name = assetPath.split('/').last;
    final dir = await _cacheDir();
    final file = dir == null ? null : File('${dir.path}/$name');
    if (file != null) {
      try {
        if (await file.exists()) {
          // Beim Lesen die Zeit anfassen: Danach entscheidet das
          // Aufräumen, was am längsten nicht gesehen wurde.
          final bytes = await file.readAsBytes();
          unawaited(file.setLastAccessed(DateTime.now()));
          return bytes;
        }
      } catch (e, s) {
        logError('Bild aus dem Speicher lesen', e, s);
      }
    }
    final bytes = await _fetch('$baseUrl/$name');
    if (bytes == null) return null;
    if (file != null) {
      // **Erst schreiben, dann aufräumen.** Andersherum könnte das
      // gerade geholte Bild dem Aufräumen zum Opfer fallen.
      try {
        await file.writeAsBytes(bytes, flush: true);
        await _prune(dir!);
      } catch (e, s) {
        logError('Bild ablegen', e, s);
      }
    }
    return bytes;
  }

  Future<Uint8List?> _fetch(String url) async {
    try {
      final request = await _client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      // Ohne Empfang ist das der Normalfall, nicht der Fehlerfall — das
      // mitgelieferte Bild steht ja. Deshalb auch kein `logError`:
      // Jeder Waldgang füllte sonst den Wochendigest (Lehre aus #124).
      return null;
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
      if (total <= kSpeciesPhotoCacheBytes) return;
      files.sort((a, b) => a.seen.compareTo(b.seen));
      for (final f in files) {
        if (total <= kSpeciesPhotoCacheBytes) break;
        await f.file.delete();
        total -= f.size;
      }
    } catch (e, s) {
      logError('Bildspeicher aufräumen', e, s);
    }
  }
}

/// `unawaited` ohne `dart:async` zu importieren — das Anfassen der
/// Zugriffszeit darf das Lesen nicht aufhalten und darf auch scheitern.
void unawaited(Future<void> future) {
  future.catchError((_) {});
}
