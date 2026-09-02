import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Live-Position des Nutzers für den Karten-Marker. Liefert null, wenn
/// Standortdienste aus sind oder die Berechtigung (noch) fehlt — es wird
/// hier bewusst NICHT nach der Berechtigung gefragt, das übernimmt der
/// „Meine Position"-Button; danach wird dieser Provider invalidiert.
final positionStreamProvider = StreamProvider<Position?>((ref) async* {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      yield null;
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      yield null;
      return;
    }
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // erst ab 10 m Bewegung neu zeichnen
      ),
    );
  } catch (_) {
    yield null; // Position ist nice-to-have, nie ein Fehlerfall
  }
});

/// Ein EINZELNER Fix — und die einzige Stelle der App, die nach der
/// Standortberechtigung fragt.
///
/// Bewusst getrennt von [positionStreamProvider], weil beide eine andere
/// Frage beantworten: Der Strom fragt NIE (sonst stünde beim ersten Start
/// ein Systemdialog mitten in der geführten Tour), dieser hier fragt
/// immer — er läuft ausschließlich nach einem sichtbaren Tipp. Genau
/// diese Trennung ist die Zusage, auf der der Abschnitt „Prominent
/// Disclosure" in `docs/play-console.md` steht.
///
/// Als Provider und nicht als Methode im Karten-Screen: Sonst ginge jeder
/// Test, der „Meine Position", das Standort-Teilen oder die Fund-Position
/// antippt, an einen Plattform-Kanal, den es im Widget-Test nicht gibt —
/// und scheiterte dort an der Technik statt an der Sache. Dieselbe Naht
/// wie `tourFixProvider` (`features/tour/tour_providers.dart`).
typedef PositionFix = Future<Position?> Function();

final positionFixProvider = Provider<PositionFix>((ref) => _platformFix);

Future<Position?> _platformFix() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}
