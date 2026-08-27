// Die Regel der Pilztour (#338): Wer gilt als abgesucht, wer als
// vorbeigegangen — und vor allem, wer NICHT als abgesucht gilt.
//
// Die Hälfte dieser Tests prüft, dass etwas ausbleibt. Das ist Absicht:
// Ein übersehener Leergang kostet eine Zeile, ein erfundener vergiftet die
// Stichprobe, die #199 für die Ampel-Validierung aufhebt. Die
// Fehlerrichtung ist Teil der Spezifikation, nicht Geschmack.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/nearby_spots.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';
import 'package:pilzbuddy/models/spot.dart';

void main() {
  const spotLat = 51.0;
  const spotLng = 11.0;

  Spot spotAt({
    String id = 's1',
    double lat = spotLat,
    double lng = spotLng,
    bool own = true,
  }) =>
      Spot(id: id, ownerId: own ? 'me' : 'du', lat: lat, lng: lng, isOwn: own);

  final start = DateTime.utc(2026, 8, 27, 9);

  /// Eine Punktreihe an EINER Stelle: [count] Fixes im Abstand [everyS].
  ///
  /// [offsetM] verschiebt sie nach Norden — bequem, weil ein Grad Breite
  /// überall 111,2 km ist und die Entfernung damit vorhersagbar bleibt.
  List<TourPoint> stayingAt({
    int count = 5,
    int everyS = 15,
    double offsetM = 0,
    double accuracyM = 8,
    DateTime? from,
  }) =>
      [
        for (var i = 0; i < count; i++)
          TourPoint(
            lat: spotLat + offsetM / 111200,
            lng: spotLng,
            at: (from ?? start).add(Duration(seconds: i * everyS)),
            accuracyM: accuracyM,
          ),
      ];

  group('tourVisits — die drei Zonen', () {
    test('im Radius und lang genug: abgesucht', () {
      // Fünf Fixes à 15 s sind vier Abschnitte = 60 s, also genau die
      // Schwelle. Dass die Grenze EINSCHLIESST, ist eine Entscheidung —
      // andernfalls verlöre der Regelfall (15-s-Takt, eine Minute
      // gesucht) den Leergang um eine Sekunde.
      final visits = tourVisits(stayingAt(), [spotAt()]);
      expect(visits, hasLength(1));
      expect(visits.single.kind, TourVisitKind.searched);
      expect(visits.single.dwell, kTourMinDwell);
    });

    test('im Radius, aber zu kurz: nur kurz da', () {
      final visits = tourVisits(stayingAt(count: 3), [spotAt()]);
      expect(visits.single.kind, TourVisitKind.brief);
      expect(visits.single.dwell, const Duration(seconds: 30));
    });

    test('nur im doppelten Radius gestreift: vorbeigegangen', () {
      // 30 m: außerhalb der 20 m, innerhalb der 40 m. Lange dort
      // gestanden zu haben ändert daran nichts — der Radius entscheidet
      // die Zone, die Uhr nur innerhalb davon.
      final visits =
          tourVisits(stayingAt(count: 20, offsetM: 30), [spotAt()]);
      expect(visits.single.kind, TourVisitKind.passedBy);
      expect(visits.single.closestM, closeTo(30, 1));
    });

    test('jenseits des doppelten Radius: steht gar nicht in der Liste', () {
      expect(tourVisits(stayingAt(offsetM: 60), [spotAt()]), isEmpty);
    });

    test('die Bänder hängen an EINER Konstante', () {
      // Wer `kNearbySpotMeters` verschiebt, verschiebt beide Grenzen mit.
      // Zwei unabhängige Radien wären zwei Antworten auf „derselbe Ort".
      final justInside = stayingAt(count: 20, offsetM: kNearbySpotMeters - 2);
      final justOutside = stayingAt(count: 20, offsetM: kNearbySpotMeters + 2);
      final farOutside = stayingAt(
          count: 20, offsetM: kNearbySpotMeters * kTourPassByFactor + 2);
      expect(tourVisits(justInside, [spotAt()]).single.kind,
          TourVisitKind.searched);
      expect(tourVisits(justOutside, [spotAt()]).single.kind,
          TourVisitKind.passedBy);
      expect(tourVisits(farOutside, [spotAt()]), isEmpty);
    });
  });

  group('tourVisits — was NICHT als abgesucht durchgeht', () {
    test('unscharfe Fixes zählen keine Verweildauer', () {
      // Genau der Fall aus dem Wald: Kronendach, gemeldete Streuung über
      // der Schranke. Räumlich sieht es aus wie eine Stunde am Spot, aber
      // entscheiden lässt sich damit nichts.
      final visits = tourVisits(
          stayingAt(count: 20, accuracyM: kTourUsableAccuracyM + 10),
          [spotAt()]);
      expect(visits.single.kind, TourVisitKind.brief);
      expect(visits.single.dwell, Duration.zero);
    });

    test('… bleiben aber in der Liste, mit ihrer Entfernung', () {
      // Der Grund, warum sie nicht einfach verworfen werden: Sonst
      // verschwände ein wirklich abgesuchter Spot unter dichtem
      // Kronendach ganz aus dem Blatt. So steht er verblasst da, einen
      // Tipp vom Eintragen entfernt.
      final visits = tourVisits(
          stayingAt(count: 20, accuracyM: 999), [spotAt()]);
      expect(visits, hasLength(1));
      expect(visits.single.closestM, closeTo(0, 1));
    });

    test('eine Lücke in der Aufzeichnung ist keine Verweildauer', () {
      // Zwei Fixes am selben Ort, zwanzig Minuten auseinander: Der
      // Prozess war eingefroren. Ohne die Schranke wären das zwanzig
      // Minuten „gesucht" — aus Unwissen wird sonst Evidenz.
      final visits = tourVisits([
        ...stayingAt(count: 1),
        ...stayingAt(count: 1, from: start.add(const Duration(minutes: 20))),
      ], [
        spotAt()
      ]);
      expect(visits.single.dwell, Duration.zero);
      expect(visits.single.kind, TourVisitKind.brief);
    });

    test('eine rückwärts laufende Uhr zählt nicht', () {
      // Sommerzeit-Umstellung oder eine gestellte Geräteuhr: Ein
      // negativer Abstand darf keine Verweildauer werden — und schon gar
      // keine negative, die eine spätere aufhebt.
      final visits = tourVisits([
        TourPoint(lat: spotLat, lng: spotLng, at: start, accuracyM: 5),
        TourPoint(
            lat: spotLat,
            lng: spotLng,
            at: start.subtract(const Duration(hours: 1)),
            accuracyM: 5),
      ], [
        spotAt()
      ]);
      expect(visits.single.dwell, Duration.zero);
    });

    test('ein Rand-Abschnitt zählt nur, wenn BEIDE Enden drin liegen', () {
      // Hereinlaufen, kurz stehen, hinauslaufen. Die beiden
      // Übergangs-Abschnitte zählen nicht — das rechnet an den Rändern
      // eher zu wenig, und zu wenig ist hier die harmlose Richtung.
      final visits = tourVisits([
        TourPoint(
            lat: spotLat + 100 / 111200,
            lng: spotLng,
            at: start,
            accuracyM: 5),
        ...stayingAt(count: 3, from: start.add(const Duration(seconds: 15))),
        TourPoint(
            lat: spotLat + 100 / 111200,
            lng: spotLng,
            at: start.add(const Duration(seconds: 75)),
            accuracyM: 5),
      ], [
        spotAt()
      ]);
      expect(visits.single.dwell, const Duration(seconds: 30));
    });

    test('fremde Spots kommen nicht vor', () {
      // Einen Leergang am Spot eines Buddys zu buchen, wäre eine Aussage
      // über dessen Fundstelle. Dieselbe Regel wie in `nearestOwnSpot`.
      expect(tourVisits(stayingAt(), [spotAt(own: false)]), isEmpty);
    });

    test('ohne Punkte und ohne Spots passiert nichts', () {
      expect(tourVisits(const [], [spotAt()]), isEmpty);
      expect(tourVisits(stayingAt(), const []), isEmpty);
    });
  });

  group('tourVisits — Reihenfolge', () {
    test('abgesucht, dann kurz, dann vorbeigegangen — und je näher, desto '
        'weiter oben', () {
      // Zwei Aufenthalte, weit genug auseinander, dass zwischen ihnen kein
      // Abschnitt zählt: eine Minute am Ursprung, fünfzehn Sekunden 100 m
      // weiter. Die beiden übrigen Spots liegen 25 und 35 m vom ersten
      // Aufenthalt entfernt, also im Vorbeigeh-Band.
      //
      // Der erste Anlauf dieses Tests war wertlos und hat es nicht
      // gezeigt: Dort lagen zwei EINZELNE Punkte 60 s auseinander, und
      // beide lagen zufällig im Radius derselben zwei Spots — die bekamen
      // damit eine volle Minute geschenkt und galten als abgesucht. Die
      // Zeitabstände sind hier deshalb Teil der Aussage.
      final visits = tourVisits([
        ...stayingAt(count: 5),
        ...stayingAt(
            count: 2,
            offsetM: 100,
            from: start.add(const Duration(minutes: 30))),
      ], [
        // Absichtlich in der „falschen" Reihenfolge übergeben.
        spotAt(id: 'fern', lat: spotLat + 35 / 111200),
        spotAt(id: 'nah', lat: spotLat + 25 / 111200),
        spotAt(id: 'kurz', lat: spotLat + 100 / 111200),
        spotAt(id: 'gesucht'),
      ]);

      expect([for (final v in visits) v.spot.id],
          ['gesucht', 'kurz', 'nah', 'fern']);
      expect([for (final v in visits) v.kind], [
        TourVisitKind.searched,
        TourVisitKind.brief,
        TourVisitKind.passedBy,
        TourVisitKind.passedBy,
      ]);
      expect(visits[1].dwell, const Duration(seconds: 15));
      expect(visits[2].closestM, closeTo(25, 1));
      expect(visits[3].closestM, closeTo(35, 1));
    });
  });

  group('TourPoint — Speicherform', () {
    test('hin und zurück', () {
      final point = TourPoint(
          lat: 51.5,
          lng: 11.25,
          at: DateTime.utc(2026, 8, 27, 9, 30),
          accuracyM: 7.5);
      final back = TourPoint.fromJson(point.toJson())!;
      expect(back.lat, point.lat);
      expect(back.lng, point.lng);
      expect(back.at, point.at);
      expect(back.accuracyM, point.accuracyM);
    });

    test('eine kaputte Zeile wird zu null, nicht zu einem Fehler', () {
      expect(TourPoint.fromJson(const {'lat': 51.0}), isNull);
      expect(TourPoint.fromJson(const {'lat': 51.0, 'lng': 11.0}), isNull);
    });

    test('fehlende Genauigkeit heißt unbrauchbar, nicht perfekt', () {
      // Die harmlose Fehlerrichtung: Der Spot landet in der verblassten
      // Hälfte, statt einen Leergang zu erfinden.
      final point =
          TourPoint.fromJson({'lat': 51.0, 'lng': 11.0, 'at': '2026-08-27T09:00:00Z'})!;
      expect(point.accuracyM, double.infinity);
      expect(point.accuracyM, greaterThan(kTourUsableAccuracyM));
    });
  });
}
