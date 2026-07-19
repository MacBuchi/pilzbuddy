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
