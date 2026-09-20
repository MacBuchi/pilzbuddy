// Wann die eigene Spur zu den Buddys geht (#340, Stufe 2).
//
// Die Regel ist rein, also wird sie hier ohne Uhr, ohne Netz und ohne
// Provider geprüft. Die teure Hälfte ist nicht „lädt hoch", sondern
// „lädt NICHT hoch" — jede Zeile hier ist eine Bedingung, unter der
// Bewegungsdaten das Gerät verlassen dürfen.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/tour/tour_sharing.dart';

void main() {
  final now = DateTime.utc(2026, 9, 20, 12);
  final sharingUntil = now.add(const Duration(hours: 2));

  TrackShareAction plan({
    bool tourRunning = true,
    int pointCount = 10,
    DateTime? shareExpiresAt,
    DateTime? lastUploadAt,
    int lastUploadedCount = 0,
  }) =>
      planTrackShare(
        tourRunning: tourRunning,
        pointCount: pointCount,
        shareExpiresAt: shareExpiresAt,
        lastUploadAt: lastUploadAt,
        lastUploadedCount: lastUploadedCount,
        now: now,
      );

  group('Ohne beide Voraussetzungen verlässt nichts das Gerät', () {
    test('Tour läuft, aber niemand teilt', () {
      // Stufe 1 unverändert: Wer aufzeichnet, ohne zu teilen, behält
      // seine Spur. Das ist die Zusage, die Patch 023 nur für den
      // anderen Fall bricht.
      expect(plan(shareExpiresAt: null), TrackShareAction.nothing);
    });

    test('Freigabe läuft, aber keine Tour', () {
      expect(plan(tourRunning: false, shareExpiresAt: sharingUntil),
          TrackShareAction.nothing);
    });

    test('Eine abgelaufene Freigabe zählt nicht', () {
      expect(plan(shareExpiresAt: now.subtract(const Duration(minutes: 1))),
          TrackShareAction.nothing);
    });
  });

  group('Zurücknehmen, sobald eine Voraussetzung wegfällt', () {
    test('Tour beendet — die hochgeladene Spur wird gelöscht', () {
      // Nicht erst beim Ablauf von `expires_at`: Bis dahin läge dort
      // eine Freigabe, die niemand mehr gibt.
      expect(
          plan(
              tourRunning: false,
              shareExpiresAt: sharingUntil,
              lastUploadAt: now.subtract(const Duration(minutes: 5))),
          TrackShareAction.remove);
    });

    test('Teilen beendet — dito', () {
      expect(
          plan(
              shareExpiresAt: null,
              lastUploadAt: now.subtract(const Duration(minutes: 5))),
          TrackShareAction.remove);
    });

    test('Nie hochgeladen ⇒ nichts zu löschen', () {
      // `remove` wäre ein Aufruf ins Leere — und einer, der bei jedem
      // Positions-Tick ohne Tour erneut liefe.
      expect(plan(tourRunning: false, shareExpiresAt: sharingUntil),
          TrackShareAction.nothing);
    });
  });

  group('Der Takt', () {
    test('Der erste Upload passiert sofort', () {
      expect(plan(shareExpiresAt: sharingUntil), TrackShareAction.upload);
    });

    test('Innerhalb der Minute wird nicht erneut hochgeladen', () {
      expect(
          plan(
              shareExpiresAt: sharingUntil,
              lastUploadAt: now.subtract(const Duration(seconds: 30)),
              lastUploadedCount: 5),
          TrackShareAction.nothing);
    });

    test('Nach der Minute wieder', () {
      expect(
          plan(
              shareExpiresAt: sharingUntil,
              lastUploadAt: now.subtract(kTrackUploadInterval),
              lastUploadedCount: 5),
          TrackShareAction.upload);
    });

    test('Ohne neue Punkte passiert nichts, auch nach der Minute', () {
      // Ein Upsert mit denselben Punkten kostet Egress und ändert
      // nichts — `updated_at` soll etwas bedeuten.
      expect(
          plan(
              shareExpiresAt: sharingUntil,
              pointCount: 5,
              lastUploadAt: now.subtract(const Duration(minutes: 10)),
              lastUploadedCount: 5),
          TrackShareAction.nothing);
    });
  });

  test('Unter zwei Punkten gibt es keine Spur', () {
    // Einen einzelnen Punkt zeigt der Standort-Marker bereits; ihn als
    // „Spur" zu teilen behauptet einen Weg, den es nicht gibt.
    expect(plan(shareExpiresAt: sharingUntil, pointCount: 1),
        TrackShareAction.nothing);
    expect(plan(shareExpiresAt: sharingUntil, pointCount: 2),
        TrackShareAction.upload);
  });
}
