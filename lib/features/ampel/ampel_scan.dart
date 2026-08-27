// Baustein B des Ampel-Konzepts (#277): Beim Kartenstart einmal durch die
// EIGENEN Spots sehen und melden, wo die Ampel günstig steht.
//
// **Warum hier und nicht auf dem Server.** Ein nächtlicher Push müsste
// Regen-, Stations- und Höhendaten erneut vorhalten und das Modell ein
// DRITTES Mal führen — neben `ampel_model.dart` und
// `tool/ampel_validate.py`. CLAUDE.md verlangt, dass die Dart-Fassung
// „Zahl für Zahl Spiegel des Validierungswerkzeugs" bleibt; eine dritte
// Kopie ist genau die Stelle, an der das unbemerkt auseinanderläuft.
// Hier fällt kein Modell an: [ampelScanOf] ruft dasselbe
// `ampelReadingFrom`, das auch das Spot-Blatt benutzt.
//
// **Was es dafür aufgibt:** Es erreicht einen beim Öffnen der App — also
// genau dann, wenn man es am wenigsten braucht. Dafür ohne Server, ohne
// Hintergrundarbeit und ohne zweites Modell. Trägt die Aussage, kann
// dieselbe Rechnung später eine echte Meldung speisen.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../models/spot.dart';
import '../map/elevation_grid.dart';
import '../map/elevation_providers.dart';
import '../map/rain_data_providers.dart';
import '../map/rain_stack.dart';
import '../map/spot_weather.dart';
import '../spots/spot_providers.dart';
import 'ampel_model.dart';
import 'ampel_providers.dart';

/// Ein Spot, an dem die Ampel günstig steht, samt seiner Ablesung.
typedef AmpelHit = ({Spot spot, AmpelReading reading});

/// Prüft die App beim Start die eigenen Spots? Muster
/// [AmpelPreviewEnabledNotifier]: Zustand springt sofort, Speichern läuft
/// nach, ein Fehler beim Merken wird nur protokolliert.
class AmpelBannerEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).ampelBannerEnabled;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setAmpelBannerEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Ampel-Banner merken', e, stackTrace);
    }));
  }
}

final ampelBannerEnabledProvider =
    NotifierProvider<AmpelBannerEnabledNotifier, bool>(
        AmpelBannerEnabledNotifier.new);

/// Die eigenen Spots mit GÜNSTIGER Ampel — bester zuerst.
///
/// [courses] liegt parallel zu [spots]; fehlt ein Eintrag, wird der Spot
/// wie ohne Regendaten behandelt und fällt damit heraus. Genau das ist
/// gewollt: Eine graue Ablesung ist eine Antwort („keine Aussage"), aber
/// kein Grund, jemanden in den Wald zu schicken.
///
/// Es zählt AUSSCHLIESSLICH [AmpelLevel.guenstig]. „Verhalten" wäre die
/// Mehrzahl der Tage und damit ein Banner, das immer steht — und ein
/// Banner, das immer steht, sagt nichts mehr.
List<AmpelHit> ampelScanOf({
  required List<Spot> spots,
  required List<RainCourse?> courses,
  required WeatherTable? table,
  required ElevationGrid? elevation,
}) {
  final hits = <AmpelHit>[];
  for (final (index, spot) in spots.indexed) {
    final reading = ampelReadingFrom(
      index < courses.length ? courses[index] : null,
      table?.at(spot.lat, spot.lng),
      // `null` heißt schlicht „unkorrigiert rechnen" — dieselbe stille
      // Degradation wie im Spot-Blatt.
      spotHeightM: elevation?.heightMetersAt(spot.lat, spot.lng),
    );
    if (reading.level != AmpelLevel.guenstig) continue;
    hits.add((spot: spot, reading: reading));
  }
  // Der beste zuerst: Das Banner nennt eine Zahl und öffnet EINEN Spot,
  // und das soll der sein, der am deutlichsten dasteht.
  hits.sort((a, b) => b.reading.score!.compareTo(a.reading.score!));
  return hits;
}

/// Der Nachlauf über die eigenen Spots — leer, solange etwas fehlt.
///
/// **Die Reihenfolge der Prüfungen ist die eigentliche Aussage dieser
/// Datei.** Erst wenn alle drei Schalter stehen, wird überhaupt ein
/// Gitter angefasst; vorher kehrt der Provider um. Beobachten IST laden
/// (CLAUDE.md), und das Höhengitter sind 3,4 MB, deren Auspacken 1.99.4
/// gerade erst aus dem Startpfad genommen hat. Ein `ref.watch` weiter
/// oben in dieser Funktion holte sie lautlos zurück — für alle, nicht
/// nur für die, die das Banner bestellt haben.
final ampelScanProvider = FutureProvider<List<AmpelHit>>((ref) async {
  if (!ref.watch(ampelBannerEnabledProvider)) return const [];
  // Ohne die Vorschau gäbe es kein Blatt, in dem sich die Aussage
  // nachlesen ließe — ein Banner über ein unsichtbares Feature.
  if (!ref.watch(ampelPreviewEnabledProvider)) return const [];
  // Und ohne die Wetter-Zustimmung liegen die Daten gar nicht vor.
  //
  // Diese Zeile ist heute REDUNDANT — `rainStackProvider` prüft dieselbe
  // Zustimmung und liefert sonst `null`, der Nachlauf endete also ohnehin
  // leer (in der Gegenprobe nachgemessen: ohne diese Zeile bleibt der
  // Test grün). Sie steht trotzdem hier, weil die Vorbedingungen an EINER
  // Stelle vollständig sein sollen und weil sie den Stapel gar nicht erst
  // anfasst. Wer sie entfernt, hängt das Verhalten allein an einem
  // fremden Provider — und merkt eine Änderung dort nicht.
  if (!ref.watch(rainCourseEnabledProvider)) return const [];

  final spots = ref.watch(mySpotListProvider);
  if (spots.isEmpty) return const [];

  final courses = await ref.watch(rainCoursesProvider(
          pointsKey([for (final s in spots) (lat: s.lat, lon: s.lng)]))
      .future);
  if (courses == null) return const [];
  final table = await ref.watch(weatherTableProvider.future);
  final elevation = await ref.watch(elevationGridProvider.future);

  return ampelScanOf(
    spots: spots,
    courses: courses,
    table: table,
    elevation: elevation,
  );
});
