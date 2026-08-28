// Der Sprungbefehl an die Karte (#345).
//
// **Das Problem, das es löst.** Die Banner nennen einen Spot und öffnen
// sein Blatt — aber die Kamera stand still. Blatt zu, und man war wieder
// da, wo die App gestartet ist; bei einem Spot 30 km entfernt half nur
// noch der Name. In der ganzen App bewegte die Kamera genau zweimal
// etwas: „Meine Position" und der Long-Press.
//
// **Warum ein Provider und kein Callback.** `MapBanners` ist `const` und
// hängt drei Ebenen unter dem Karten-Screen; das Spot-Blatt ist ein Modal
// auf dem Navigator und hat den Screen gar nicht im Baum. Den
// `MapViewController` dorthin durchzureichen hieße, die Kamera jedem
// Widget in die Hand zu geben, das mal einen Spot zeigt. Hier schreibt
// jeder den Wunsch, und GENAU EINER führt ihn aus — der Karten-Screen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Wohin die Karte springen soll.
///
/// **[nonce] ist tragend, nicht Zierde** — aber nicht aus dem Grund, der
/// hier zuerst stand. Ein `NotifierProvider` vergleicht mit
/// `!identical(previous, next)`, also über die Objektidentität und NICHT
/// über `==` (riverpod 2.6.1, `notifier.dart`). Ein frisch gebautes Ziel
/// löst damit auch ohne Zähler jedes Mal aus.
///
/// Die Falle ist die Kanonisierung: `const LatLng(51, 11)` ist beim
/// zweiten Mal DASSELBE Objekt. Nachgemessen — ohne Zähler und mit
/// konstantem Ziel kommt der zweite Wunsch NICHT an (1 statt 2
/// Auslösungen), mit gebautem Ziel schon. Ein künftiger Aufrufer, der
/// eine feste Stelle als Literal schreibt, verlöre den zweiten Sprung
/// also lautlos; dasselbe gälte bei einem Wechsel auf `Provider` oder
/// `StateProvider`, die beide mit `!=` vergleichen.
///
/// Der Zähler macht jeden Zustand von seinem Vorgänger verschieden und
/// nimmt der Frage damit die Bedeutung. Verwandt mit
/// `mapAutoUpdateInputsProvider` (#332), aber andersherum: Dort dürfen
/// gleiche Zutaten NICHT auslösen, hier muss derselbe Wunsch jedes Mal.
typedef MapFocus = ({LatLng target, int nonce});

/// Zoomstufe, auf die ein Sprung mindestens geht — dieselbe Zahl wie beim
/// Long-Press, weil es dieselbe Absicht ist („zeig mir diese Stelle").
///
/// Sie wird nie unterschritten und nie erzwungen: Wer schon näher dran
/// ist, bleibt näher dran. Ein Sprung, der herauszoomt, wäre für den
/// Nutzer ein Rückschritt, keine Hilfe.
const kSpotFocusZoom = 16.0;

class MapFocusNotifier extends Notifier<MapFocus?> {
  @override
  MapFocus? build() => null;

  void focusOn(LatLng target) =>
      state = (target: target, nonce: (state?.nonce ?? 0) + 1);
}

/// Der Wunsch, die Karte zu bewegen. `null` = niemand hat bisher einen
/// gestellt; der Karten-Screen hört darauf und bewegt.
final mapFocusProvider =
    NotifierProvider<MapFocusNotifier, MapFocus?>(MapFocusNotifier.new);
