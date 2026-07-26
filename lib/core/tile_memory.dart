import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Speicherbudget für dekodierte Kachelbilder (Issue #142).
///
/// Warum das nötig ist: `flutter_map` nimmt eine Kachel beim Ausdünnen aus
/// dem Widget-Baum, gibt ihr Bild aber NICHT frei —
/// `TileImage.dispose({evictImageFromCache = false})`, und beim normalen
/// Ausdünnen übergibt das Paket `true` nur für fehlerhaft geladene Kacheln.
/// Alles andere bleibt in Flutters globalem [ImageCache] liegen, bis DER
/// seine Grenze erreicht. Die Vorgabe dort ist großzügig (1000 Bilder /
/// 100 MB) und wird zusätzlich mit Pilz-Icons und Avataren geteilt. Gemessen
/// auf einem Pixel 7 Pro: Der GPU-Texturspeicher wuchs beim Bedienen der
/// Karte von 89 auf 257 MB und fiel erst beim Neustart zurück; in den
/// ANR-Berichten stand er bei 1,7–1,9 GB RSS.
///
/// Wie andere es machen: MapLibre und Mapbox GL halten einen Kachel-Cache
/// mit fester Obergrenze und verwerfen die ältesten Kacheln samt
/// GPU-Speicher. Die Obergrenze leiten sie aus dem Sichtfeld ab
/// (`maxTileCacheSize` = `maxTileCacheZoomLevels` × Kacheln im Sichtfeld) —
/// also ein Budget statt einer geometrischen Nachbarschaft. Genau das macht
/// [tileImageBudget].
///
/// Es ist eine Umgehung, keine Behebung: Freigeben müsste das Paket beim
/// Ausdünnen. Der Zwischenspeicher wird hier nur klein genug gehalten, dass
/// seine eigene Verdrängung rechtzeitig greift.

/// Bytes einer dekodierten 256×256-Kachel (RGBA).
const _bytesPerTile = 256 * 256 * 4;

/// Wie viele Zoomstufen an Kacheln vorgehalten werden sollen. Zwei wären
/// knapp (die Stufe, aus der man kommt, und die, in der man ist), vier
/// wären wieder das alte Problem.
const _retainedZoomLevels = 3;

/// Budget für [physicalSize] (Bildschirm in physischen Pixeln).
///
/// Die Grenzen sind Leitplanken, kein Feintuning: Unter 32 MB fängt die App
/// an, sichtbare Kacheln neu zu dekodieren (Flackern statt Sparen), über
/// 96 MB ist der Sinn der Übung dahin.
({int maxBytes, int maxImages}) tileImageBudget(Size physicalSize) {
  final across = (physicalSize.width / 256).ceil();
  final down = (physicalSize.height / 256).ceil();
  final perViewport = math.max(1, across * down);
  final images = (perViewport * _retainedZoomLevels).clamp(100, 400);
  final bytes = (images * _bytesPerTile).clamp(32 << 20, 96 << 20);
  return (maxBytes: bytes, maxImages: images);
}

/// Setzt das Budget auf Flutters globalem Bild-Cache.
///
/// [physicalSize] `null` ⇒ Vorgabe für ein typisches Telefon; beim Start
/// gibt es noch keine sichere Bildschirmgröße, und ein fehlender Wert darf
/// nicht dazu führen, dass gar kein Budget gilt.
void applyTileImageBudget(Size? physicalSize) {
  final budget = tileImageBudget(physicalSize ?? const Size(1080, 2400));
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = budget.maxBytes
    ..maximumSize = budget.maxImages;
}
