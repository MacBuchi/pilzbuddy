// Bild-Overlays in der MapLibre-Engine — imperativ, nicht im Style.
//
// **Warum nicht im Style-Dokument**, wo die DWD-Bildebene liegt: Der
// Style entsteht einmal und ändert sich fast nie (Anti-Race aus der
// Spike-Autopsie, siehe `maplibre_style_provider.dart`); die Flächen
// ändern sich unabhängig davon. Hinge der Style an ihnen, käme bei jedem
// Wechsel ein vollständiges `setStyle` — für ein Bild, das sich auch
// einzeln austauschen lässt. Der Versuch hat seinerzeit neun Tests in
// eine Zeitüberschreitung laufen lassen.
//
// Aus `maplibre_rain_fill.dart` verallgemeinert, als mit der
// Waldtypen-Ebene (#213) der zweite Nutzer kam — genau der Fall, den die
// Datei damals als „trägt später das Ampel-Raster" angekündigt hat.
import 'package:maplibre/maplibre.dart' as ml;

/// Ein Bild samt der Grenzen, auf die es gehört.
///
/// Die Grenzen kommen IMMER vom Bild selbst mit, nie aus einer
/// Konstante: Beim Regen lagen Gitter- und Ebenen-Grenzen einmal rund
/// zwanzig Kilometer auseinander, und die Fläche saß sichtbar neben den
/// Linien.
typedef ImageFill = ({
  String url,
  double west,
  double east,
  double north,
  double south,
});

/// Die Bildquelle zu einem [ImageFill].
ml.ImageSource imageFillSource(String sourceId, ImageFill fill) =>
    ml.ImageSource(
      id: sourceId,
      url: fill.url,
      coordinates: ml.LngLatQuad(
        topLeft: ml.Geographic(lon: fill.west, lat: fill.north),
        topRight: ml.Geographic(lon: fill.east, lat: fill.north),
        bottomRight: ml.Geographic(lon: fill.east, lat: fill.south),
        bottomLeft: ml.Geographic(lon: fill.west, lat: fill.south),
      ),
    );

/// Die Rasterebene dazu.
///
/// `raster-opacity: 1` mit Absicht: Die Durchsichtigkeit steckt schon in
/// den Bildpunkten. Zweimal abgeschwächt wäre die Fläche nicht mehr zu
/// sehen.
///
/// [resampling] entscheidet der Aufrufer, weil es eine Aussage über die
/// DATEN ist: Der Regen zeichnet `linear` (die Fläche kommt aus demselben
/// geglätteten Feld wie früher die Konturen), der Wald `nearest` — dort
/// sind die 250-m-Klötzchen die Daten, und weichgezeichnet sähe das
/// Gitter genauer aus, als es ist.
ml.RasterStyleLayer imageFillStyleLayer(String layerId, String sourceId,
        {required String resampling}) =>
    ml.RasterStyleLayer(
      id: layerId,
      sourceId: sourceId,
      paint: {'raster-opacity': 1.0, 'raster-resampling': resampling},
    );

/// Hängt eine Fläche ein, tauscht sie aus oder nimmt sie weg — und
/// liefert die URL zurück, die danach auf der Karte liegt (`null` =
/// keine).
///
/// [appliedUrl] ist die URL des letzten Aufrufs; ist sie gleich, passiert
/// nichts. Nach einem `setStyle` ist alles Imperative weg — dann ruft die
/// Ansicht mit `appliedUrl: null` erneut auf.
///
/// Die Fläche wird schlicht angehängt: Über ihr liegt nichts Eigenes,
/// die Marker sind Flutter-Widgets über der ganzen Karte.
/// Braucht die Engine nach diesem [applyImageFill]-Ausgang einen Stups?
///
/// maplibre-native zeichnet nach dem ENTFERNEN einer Ebene nicht von
/// selbst neu (am Emulator gemessen, 2026-08-04) — beim Hinzufügen
/// schon, weil die ladende Quelle anstößt. Also: Stups genau dann, wenn
/// vorher etwas lag, das jetzt weg oder ersetzt ist. Beim Ersetzen ist
/// er überflüssig, aber harmlos — die Bedingung bleibt dafür simpel.
/// Der Stups gehört HINTER das tatsächliche Entfernen: Der frühere
/// Anstoß beim Provider-Wechsel kam der asynchronen Arbeit zuvor, und
/// die Fläche blieb bis zur nächsten Kamerabewegung stehen (#230).
bool fillRemovalNeedsNudge({String? before, String? after}) =>
    before != null && before != after;


Future<String?> applyImageFill(
  ml.StyleController style, {
  required String sourceId,
  required String layerId,
  required ImageFill? fill,
  required String? appliedUrl,
  required String resampling,
  String? belowLayerId,
}) async {
  if (fill?.url == appliedUrl) return appliedUrl;

  if (appliedUrl != null) {
    await style.removeLayer(layerId);
    await style.removeSource(sourceId);
  }
  if (fill == null) return null;

  await style.addSource(imageFillSource(sourceId, fill));
  // [belowLayerId] nur setzen, wenn die Ziel-Ebene wirklich liegt — der
  // Aufrufer weiß das (#232: Wald unter Regen, damit die Regenfläche
  // beim Kombinieren obenauf bleibt). Ein Verweis auf eine fehlende
  // Ebene wäre plattformabhängiges Verhalten, das niemand testet.
  await style.addLayer(
      imageFillStyleLayer(layerId, sourceId, resampling: resampling),
      belowLayerId: belowLayerId);
  return fill.url;
}
