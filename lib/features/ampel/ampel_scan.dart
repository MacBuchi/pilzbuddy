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
import '../map/spot_filter.dart'
    show currentMonthProvider, selectedAmpelClassesProvider;
import '../map/spot_weather.dart';
import '../../core/season_curves.dart';
import '../spots/spot_providers.dart';
import 'ampel_model.dart';
import 'ampel_providers.dart';

/// Ein Spot, an dem es sich gerade lohnen könnte — samt der ART, für
/// die das gilt, und ihrer Ablesung.
///
/// Die Art gehört dazu, seit der Hinweis zwei Bedingungen verbindet: Ein
/// Spot mit Pfifferling- UND Steinpilzfunden kann im Juli wegen des
/// einen dastehen und im Oktober wegen des anderen. Ohne den Namen wäre
/// „hier ist günstig" eine Aussage, die niemand mehr einer Art zuordnen
/// kann — und das Blatt darunter könnte ihr widersprechen, ohne dass es
/// auffiele. `null` ist die Gildenfrage („Steinpilz & Co.") an einem
/// Spot, an dem noch keine Art eingetragen ist.
typedef AmpelHit = ({Spot spot, AmpelReading reading, String? species});

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

/// Die eigenen Spots, an denen es sich gerade lohnen könnte — bester
/// zuerst.
///
/// **Zwei Bedingungen, und beide gelten je ART** (Betreiber,
/// 2026-09-12): Die Ampel-Klasse dieser Art muss günstig stehen, UND
/// ihre Saisonkurve muss sagen, dass sie jetzt überhaupt auftaucht. Ein
/// Spot erscheint, sobald das für mindestens eine seiner Arten
/// zusammenfällt.
///
/// **Warum je Art und nicht je Spot.** Beides über den Spot zu fragen
/// gäbe Unsinn: An einer Stelle mit Pfifferling- und Steinpilzfunden
/// stünde im Juli die Ampel des HERBSTfensters (jüngster Fund
/// Steinpilz), während das Saison-Tor wegen des PFIFFERLINGS aufginge —
/// zwei Aussagen über zwei Pilze, zu einer verrechnet. Gepaart wird
/// deshalb innerhalb der Art, und der Treffer trägt ihren Namen.
///
/// **Warum die Saison ein TOR ist und kein Faktor.** Sie darf nicht in
/// den Score: Die Rückwärtsvalidierung vergleicht den Fundtag gegen Tage
/// DERSELBEN Saison, dort kürzt sie sich heraus und ist damit
/// prinzipiell ungeprüft (`ampel_model.dart`). Als Bedingung „taucht die
/// Art jetzt überhaupt auf" ist sie dagegen eine Tatsache über
/// GBIF-Meldungen und braucht keine Validierung.
///
/// Die Regeln bei Unwissen sind die des Saison-Filters (#414) — **im
/// Zweifel zeigen**: Eine Art ohne Kurve verdeckt nichts (`null` heißt
/// „wir wissen es nicht", nicht „nein"), und ein Spot ganz ohne
/// eingetragene Art bleibt die Gildenfrage.
///
/// [courses] liegt parallel zu [spots]; fehlt ein Eintrag, wird der Spot
/// wie ohne Regendaten behandelt und fällt damit heraus. Genau das ist
/// gewollt: Eine graue Ablesung ist eine Antwort („keine Aussage"), aber
/// kein Grund, jemanden in den Wald zu schicken.
///
/// [classes] ist die Gruppenauswahl des Nutzers — dieselbe Liste, mit
/// der Fläche und Legende rechnen.
///
/// Es zählt AUSSCHLIESSLICH [AmpelLevel.guenstig]. „Verhalten" wäre die
/// Mehrzahl der Tage und damit ein Banner, das immer steht — und ein
/// Banner, das immer steht, sagt nichts mehr.
List<AmpelHit> ampelScanOf({
  required List<Spot> spots,
  required List<RainCourse?> courses,
  required WeatherTable? table,
  required ElevationGrid? elevation,
  required List<AmpelClass> classes,
  required int month,
}) {
  final hits = <AmpelHit>[];
  for (final (index, spot) in spots.indexed) {
    AmpelHit? best;
    for (final species in scanSpeciesOf(spot)) {
      final klass = ampelClassFor(species);
      // Eine Art ohne bestätigte Klasse bekommt keine Stufe — grau ist
      // eine Antwort, aber kein Grund, jemanden in den Wald zu schicken.
      if (klass == null) continue;
      // Und eine abgewählte Gruppe spricht gar nicht (Chips im Filter,
      // 1.142.0). Der Hinweis MUSS mitziehen: Er nennt eine Zahl, und
      // ein Tipp darauf setzt den Ampel-Filter — stünde im Banner „2
      // Spots" und auf der gefilterten Karte läge einer, widerspräche
      // die App sich selbst (#399, dieselbe Menge in Banner, Filter und
      // Blatt).
      if (!classes.contains(klass)) continue;
      // Das Saison-Tor. `null` heißt „keine Kurve" und damit „zeigen".
      if (!(speciesInSeason(species, month) ?? true)) continue;
      final reading = ampelReadingFrom(
        index < courses.length ? courses[index] : null,
        table?.at(spot.lat, spot.lng),
        klass: klass,
        // `null` heißt schlicht „unkorrigiert rechnen" — dieselbe stille
        // Degradation wie im Spot-Blatt.
        spotHeightM: elevation?.heightMetersAt(spot.lat, spot.lng),
      );
      if (reading.level != AmpelLevel.guenstig) continue;
      if (best == null || reading.score! > best.reading.score!) {
        best = (spot: spot, reading: reading, species: species);
      }
    }
    if (best != null) hits.add(best);
  }
  // Der beste zuerst: Das Banner nennt eine Zahl und öffnet EINEN Spot,
  // und das soll der sein, der am deutlichsten dasteht.
  hits.sort((a, b) => b.reading.score!.compareTo(a.reading.score!));
  return hits;
}

/// Die Arten eines Spots, für die gerechnet wird — jüngster Fund zuerst,
/// ohne Dopplungen.
///
/// **Leergangsfrei** (`findsSorted`, #211): Ein „nichts gefunden" trägt
/// keine Art und behauptet nichts, worüber eine Ampel zu urteilen wäre.
/// Ein Spot ohne jeden Fund liefert `[null]` — die Gildenfrage, also
/// genau das, was die Karte ohnehin rechnet.
///
/// Geteilt mit dem Spot-Blatt, damit Banner und Blatt nicht über
/// verschiedene Arten sprechen können (#279-Regel, eine Ebene tiefer).
List<String?> scanSpeciesOf(Spot spot) {
  final seen = <String>{};
  final out = <String?>[];
  for (final find in spot.findsSorted) {
    final species = find.species;
    if (species == null || !seen.add(species)) continue;
    out.add(species);
  }
  return out.isEmpty ? const [null] : out;
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

  // NACH den Schaltern und VOR dem ersten Gitter: Die Auswahl kostet
  // nichts (zwei Konstanten aus einer Map), aber die Reihenfolge in
  // dieser Funktion ist die Zusage — beobachten IST laden.
  final classes = ref.watch(selectedAmpelClassesProvider);

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
    classes: classes,
    // Derselbe Provider, an dem der Saison-Filter hängt — nicht
    // `DateTime.now()`: Banner und Filter müssen denselben Monat sehen,
    // sonst zeigt der Tipp auf eine Karte, die etwas anderes filtert.
    month: ref.watch(currentMonthProvider),
  );
});
