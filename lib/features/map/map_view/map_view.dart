import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'flutter_map_view.dart';
import 'map_engine.dart';
import 'marker_culling.dart' show MapViewBounds;
export 'marker_culling.dart' show MapViewBounds;
// Web darf `package:maplibre` nie sehen — der Stub liefert dieselbe
// Signatur, die Engine-Wahl unten verzweigt dank `!kIsWeb` nie dorthin.
import 'maplibre_view_stub.dart'
    if (dart.library.io) 'maplibre_map_view.dart';

/// Engine-neutrale Fassade der Kartenansicht.
///
/// `MapScreen` beschreibt hier nur noch, WAS die Karte zeigen soll
/// (Konfiguration, Markergruppen) und greift über [MapViewController] auf
/// die Kamera zu. WIE gerendert wird, entscheidet die Engine hinter
/// [mapViewBuilderProvider] — heute flutter_map, künftig wahlweise
/// MapLibre (Migrationsplan „Lupo → Porsche"), im Test eine Fake ohne
/// Kacheln. Alles, was über der Karte liegt (Fadenkreuz, Banner, FABs,
/// Sheets), bleibt gewöhnliche Flutter-UI im Stack von `map_screen.dart`
/// und weiß nichts von der Engine.

/// Was die Karte können muss — unabhängig von der Engine.
class MapViewConfig {
  const MapViewConfig({
    required this.initialCenter,
    required this.initialZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.backgroundColor,
    this.onLongPress,
    this.onCameraIdle,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final double minZoom;
  final double maxZoom;

  /// Fläche, wo (noch) keine Kachel liegt — Landton statt „kaputtem" Grau.
  final Color backgroundColor;

  /// Long-Press auf die Karte (richtet das Fadenkreuz aus).
  final void Function(LatLng latLng)? onLongPress;

  /// Die Karte ist zum Stehen gekommen — mit der neuen Mitte und dem
  /// Sichtfenster.
  ///
  /// BEWUSST nur bei Stillstand und nicht bei jeder Bewegung: Die
  /// Fadenkreuz-Werte der Legende (#235) rechnen daraufhin nach, und die
  /// Waldfläche plant daran ihren Bildausschnitt (#249) — beides soll die
  /// Gesten nicht begleiten, sondern ihnen folgen.
  ///
  /// **Keine Zoomstufe im Gepäck**, obwohl 1.98.0 eine mitgab: Die
  /// beiden Engines zählen sie verschieden (MapLibre in 512er-Kacheln,
  /// flutter_map in 256ern), eine Zahl über diese Grenze wäre also
  /// zweideutig. Wer den Maßstab braucht, rechnet ihn aus [bounds] und
  /// der eigenen Pixelbreite — das ist eindeutig.
  final void Function(LatLng center, MapViewBounds bounds)? onCameraIdle;
}

/// Ein Marker: Position, Maße, Widget-Kind. Wie er auf die Karte kommt
/// (flutter_map-MarkerLayer, MapLibre-WidgetLayer, Fake-Stack), entscheidet
/// die Engine.
class MapViewMarker {
  const MapViewMarker({
    required this.point,
    required this.width,
    required this.height,
    this.alignment = Alignment.center,
    required this.child,
  });

  final LatLng point;
  final double width;
  final double height;

  /// Wie beim flutter_map-Marker: Wo der Marker relativ zum Punkt hängt.
  /// `topCenter` = der Punkt liegt am unteren Rand (Pilz „steht" darauf).
  final Alignment alignment;
  final Widget child;
}

/// Ein Linienzug auf der Karte (#340).
///
/// **Die Farbe hängt an der LINIE, nicht am Layer** — das ist die
/// Entscheidung, die diese Klasse trifft, und sie ist nicht kosmetisch:
/// flutter_map kann mehrere Farben in einem Layer, MapLibre trägt die
/// Farbe am Layer und braucht deshalb einen je Linie. Die Fassade folgt
/// der freieren Form, sonst könnten zwei Buddys nie verschiedene Farben
/// haben — und genau dafür ist das Ganze da.
class MapViewPolyline {
  const MapViewPolyline({
    required this.points,
    required this.color,
    this.width = 3,
  });

  final List<LatLng> points;
  final Color color;
  final double width;
}

/// Die Ausrichtung, wie MapLibre sie versteht — **umgekehrt** zu
/// flutter_map (#409).
///
/// Beide Pakete nehmen ein `Alignment`, und beide rechnen daraus die
/// Bildschirmposition des Markers. Nur eben andersherum:
///
/// ```
/// flutter_map:  top = punkt.y - (h - 0.5*h*(y+1))
/// maplibre:     top = punkt.y -      0.5*h*(y+1)
/// ```
///
/// Bei `topCenter` (y = -1) liegt der Punkt in flutter_map an der
/// UNTERKANTE des Markers — der Pilz steht darauf — und in MapLibre an
/// der OBERKANTE, der Marker hängt also darunter. Bei `center` fällt der
/// Unterschied weg, und genau deshalb ist es so lange niemandem
/// aufgefallen: Bis 1.120.0 benutzte NUR der Spot-Marker etwas anderes
/// als `center`.
///
/// Die Fassade folgt flutter_map (so steht es an [MapViewMarker]), also
/// muss die MapLibre-Seite spiegeln. `* -1` ist genau das: Aus
/// `topCenter` wird `bottomCenter`.
///
/// Gemeldet wurde es an den Standort-Tropfen aus #403, weil deren Spitze
/// eine genaue Aussage macht — ein Pilz, der 44 px zu tief steht, sieht
/// nur ungenau aus. Betroffen war der Spot-Marker seit 1.43.0 mit.
Alignment mapLibreAlignment(Alignment facadeAlignment) =>
    facadeAlignment * -1;

/// Die Markergruppen in fester Zeichenreihenfolge (unten → oben):
/// Tour-Spur < Freunde-Live < eigene Position < Spots — damit Spots
/// tappbar bleiben.
///
/// **Der eigene Standort liegt über dem der Buddys** (#403). Vorher lag
/// er darunter: Wer mit jemandem zusammen sucht, stand genau dann nicht
/// mehr auf der Karte, wenn beide dicht beieinander waren — also im
/// einzigen Moment, in dem man beide Punkte auseinanderhalten will. Über
/// die SPOTS geht er weiterhin nicht; die sollen tappbar bleiben.
///
/// Die Spur liegt ganz unten, und das ist Absicht: Sie ist Hintergrund,
/// kein Inhalt. Über den Spots läge sie ausgerechnet dort, wo man
/// tippen will — nämlich auf den Fundstellen, die man gerade abgelaufen
/// ist.
///
/// Warum Marker und keine Linie: Die Fassade kennt keine Polylinien, und
/// beide Engines müssten sie getrennt bekommen. Punkte („Linienpunkte",
/// so der Betreiber in #338) sagen zudem etwas, was eine Linie
/// verschweigt — wo die Abstände eng sind, hat man gesucht.
class MapViewMarkers {
  const MapViewMarkers({
    this.polylines = const [],
    this.tourTrack = const [],
    this.myPosition = const [],
    this.friendLocations = const [],
    this.spots = const [],
  });

  /// Linienzüge, GANZ unten — noch unter der Tour-Spur.
  ///
  /// Der Name der Klasse sagt „Markers" und meint inzwischen alles, was
  /// über der Karte liegt. Ein eigener Behälter daneben wäre ehrlicher
  /// und hätte fünf Aufrufstellen samt Fake angefasst; die Linie ist
  /// hier eingezogen, weil sie dieselbe Reise nimmt.
  final List<MapViewPolyline> polylines;

  final List<MapViewMarker> tourTrack;
  final List<MapViewMarker> myPosition;
  final List<MapViewMarker> friendLocations;
  final List<MapViewMarker> spots;
}

/// Kamerazugriff der Engine — sie hängt sich beim Einbau per
/// [MapViewController.attach] ein.
abstract class MapViewCameraDelegate {
  void move(LatLng center, double zoom);
  LatLng get center;
  double get zoom;
}

/// Engine-unabhängiger Griff an die Kamera für `MapScreen` („Meine
/// Position", „Neuer Spot" an der Kartenmitte, Long-Press-Zoom).
///
/// Vor dem Einbau der Engine antworten [center]/[zoom] mit den Startwerten
/// — dieselbe Semantik wie eine noch nicht bewegte Karte.
class MapViewController {
  MapViewController({
    required LatLng initialCenter,
    required double initialZoom,
  })  : _center = initialCenter,
        _zoom = initialZoom;

  MapViewCameraDelegate? _delegate;
  LatLng _center;
  double _zoom;

  void attach(MapViewCameraDelegate delegate) => _delegate = delegate;

  /// Nur der aktuell eingehängte Delegate darf sich lösen — beim Wechsel
  /// der Engine läuft `attach` des Neuen vor `dispose` des Alten.
  void detach(MapViewCameraDelegate delegate) {
    if (identical(_delegate, delegate)) _delegate = null;
  }

  void move(LatLng center, double zoom) {
    final delegate = _delegate;
    if (delegate == null) {
      // Karte noch nicht da: Wunsch als neuen „Startzustand" merken.
      _center = center;
      _zoom = zoom;
      return;
    }
    delegate.move(center, zoom);
  }

  LatLng get center => _delegate?.center ?? _center;
  double get zoom => _delegate?.zoom ?? _zoom;
}

/// Baut die Kartenansicht einer konkreten Engine.
typedef MapViewBuilder = Widget Function(
  MapViewConfig config,
  MapViewController controller,
  MapViewMarkers markers,
);

/// Die Engine-Wahl: flutter_map ist Standard, MapLibre kommt nur per
/// Opt-in-Schalter (Beta, Profil) und nie im Web. Tests überschreiben den
/// Provider mit der Fake (`test/fakes/fake_map_view.dart`).
final mapViewBuilderProvider = Provider<MapViewBuilder>((ref) {
  if (!kIsWeb && ref.watch(mapLibreEnabledProvider)) {
    return (config, controller, markers) => createMapLibreMapView(
        config: config, controller: controller, markers: markers);
  }
  return (config, controller, markers) => FlutterMapView(
        config: config,
        controller: controller,
        markers: markers,
      );
});

/// Das Fassaden-Widget, das `MapScreen` einbaut.
class MapView extends ConsumerWidget {
  const MapView({
    super.key,
    required this.config,
    required this.controller,
    required this.markers,
  });

  final MapViewConfig config;
  final MapViewController controller;
  final MapViewMarkers markers;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(mapViewBuilderProvider)(config, controller, markers);
}
