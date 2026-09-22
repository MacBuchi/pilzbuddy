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

import 'file_cache.dart';

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
/// **Eine Größengrenze, keine Frist** — warum, steht in
/// `file_cache.dart`, wo das Aufräumen seit #532 für alle Bildspeicher
/// wohnt.
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
  })  : _client = client ?? HttpClient(),
        _cache = BoundedFileCache(
            dirName: 'species_photos',
            maxBytes: kSpeciesPhotoCacheBytes,
            enabled: cachesToDisk);

  final HttpClient _client;

  /// **Nur damit der Test ohne Netz auskommt.** Die Projektregel lautet
  /// „kein Netzwerk in Tests"; ohne diesen Haken liefe der Fall „Abruf
  /// scheitert" gegen den echten Dienst und wäre in CI ein Flatterer.
  final String baseUrl;

  /// **Im Browser speichern wir nichts selbst** — Begründung in
  /// `file_cache.dart`, wo der Speicher seit #532 wohnt.
  final bool cachesToDisk;

  final BoundedFileCache _cache;

  /// Das große Bild zu einem Asset-Pfad — `null`, wenn es nicht zu
  /// holen war.
  ///
  /// Der Dateiname ist derselbe wie im Asset-Ordner, das ist die ganze
  /// Zuordnung. Eine zweite Tabelle wäre die Stelle, an der ein
  /// getauschtes Bild seinen alten Namen behält.
  Future<Uint8List?> load(String assetPath) async {
    final name = assetPath.split('/').last;
    final cached = await _cache.read(name);
    if (cached != null) return cached;
    final bytes = await _fetch('$baseUrl/$name');
    if (bytes == null) return null;
    await _cache.write(name, bytes);
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
}
