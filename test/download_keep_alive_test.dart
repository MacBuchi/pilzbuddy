// Der geteilte Foreground-Service (#264).
//
// Karten-Download und Wald-Vorlauf laufen im selben Prozess und brauchen
// beide denselben Service. Vor dem Koordinator beendete das `stop()` des
// einen ihn dem anderen mitten im Lauf — und ein eingefrorener Prozess
// ist genau der Fehler, gegen den der Service da ist.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/download_keep_alive.dart';

import 'fakes/fake_keep_alive.dart';

void main() {
  late FakeKeepAlive service;
  late DownloadKeepAliveCoordinator coordinator;

  setUp(() {
    service = FakeKeepAlive();
    coordinator = DownloadKeepAliveCoordinator(service);
  });

  test('zwei Downloads teilen sich EINEN Service', () async {
    await coordinator.start('maps', 'Berlin — 10 %',
        title: 'Offline-Daten werden geladen');
    await coordinator.start('forest', 'Feine Waldkarte — 0 %',
        title: 'Offline-Daten werden geladen');

    expect(service.running, isTrue);
    expect(service.starts, 1, reason: 'nicht zwei Services nebeneinander');
  });

  test('der Service endet erst, wenn der letzte gegangen ist', () async {
    await coordinator.start('maps', 'Berlin — 10 %',
        title: 'Offline-Daten werden geladen');
    await coordinator.start('forest', 'Feine Waldkarte — 0 %',
        title: 'Offline-Daten werden geladen');

    await coordinator.stop('maps');
    expect(service.running, isTrue,
        reason: 'der Wald-Vorlauf läuft noch — sein Prozess darf nicht '
            'eingefroren werden');

    await coordinator.stop('forest');
    expect(service.running, isFalse,
        reason: 'eine Dauerbenachrichtigung wäre grob unhöflich');
  });

  test('der Text nennt, was gerade läuft', () async {
    await coordinator.start('maps', 'Berlin — 10 %',
        title: 'Offline-Daten werden geladen');
    await coordinator.start('forest', 'Feine Waldkarte — 0 %',
        title: 'Offline-Daten werden geladen');
    expect(service.texts.last, contains('Berlin'));
    expect(service.texts.last, contains('Waldkarte'));

    // Nach dem Abmelden verschwindet der Melder auch aus dem Text.
    await coordinator.stop('maps');
    expect(service.texts.last, isNot(contains('Berlin')));
    expect(service.texts.last, contains('Waldkarte'));
  });

  test('unveränderter Text geht nicht über den Kanal', () async {
    // Sonst schickte jeder einzelne Chunk eine Aktualisierung.
    await coordinator.start('maps', 'Berlin — 10 %',
        title: 'Offline-Daten werden geladen');
    final before = service.texts.length;
    await coordinator.update('maps', 'Berlin — 10 %');
    expect(service.texts, hasLength(before));

    await coordinator.update('maps', 'Berlin — 11 %');
    expect(service.texts, hasLength(before + 1));
  });

  test('ein unbekannter Schlüssel tut nichts', () async {
    await coordinator.start('maps', 'Berlin — 10 %',
        title: 'Offline-Daten werden geladen');

    // Ein Nachzügler nach dem eigenen stop() darf den Service weder
    // beschriften noch beenden — und auch keinen Kanalaufruf kosten.
    final before = service.texts.length;
    await coordinator.update('forest', 'Feine Waldkarte — 50 %');
    expect(service.texts, hasLength(before));
    expect(service.texts.last, contains('Berlin'));

    await coordinator.stop('forest');
    expect(service.running, isTrue);
    expect(service.texts, hasLength(before));
  });

  test('doppeltes stop beendet nichts zweimal', () async {
    await coordinator.start('maps', 'Berlin — 10 %',
        title: 'Offline-Daten werden geladen');
    await coordinator.stop('maps');
    expect(service.running, isFalse);

    await coordinator.start('forest', 'Feine Waldkarte — 0 %',
        title: 'Offline-Daten werden geladen');
    await coordinator.stop('maps');
    expect(service.running, isTrue,
        reason: 'der zweite Abmeldeversuch gehört einem Melder, der weg ist');
  });

  group('Service-Typen (#338)', () {
    test('eine Pilztour startet den Service als `location`', () async {
      await coordinator.start('pilztour', 'Der Weg wird aufgezeichnet',
          title: 'Pilztour läuft', types: const {KeepAliveType.location});
      expect(service.types, {KeepAliveType.location});
      expect(service.titles.last, 'Pilztour läuft');
    });

    test('kommt ein Download dazu, wird der Service NEU gestartet', () async {
      // Der Kern der Sache: `updateService` kann die Typen nicht ändern
      // (nachgesehen in flutter_foreground_task 10.0.0). Ein als
      // `location` laufender Service bliebe für den Download ohne
      // `dataSync` — und andersherum bekäme eine Tour im Hintergrund
      // keine Standorte mehr, weil Android 14 je Typ prüft.
      await coordinator.start('pilztour', 'Der Weg wird aufgezeichnet',
          title: 'Pilztour läuft', types: const {KeepAliveType.location});
      expect(service.starts, 1);

      await coordinator.start('maps', 'Berlin — 10 %',
          title: 'Offline-Daten werden geladen');
      expect(service.starts, 2, reason: 'ohne Neustart fehlte dataSync');
      expect(service.types, {KeepAliveType.location, KeepAliveType.dataSync});
    });

    test('gleiche Typen starten NICHT neu', () async {
      // Sonst risse jeder zweite Download die Benachrichtigung kurz weg.
      await coordinator.start('maps', 'Berlin — 10 %',
          title: 'Offline-Daten werden geladen');
      await coordinator.start('forest', 'Feine Waldkarte — 0 %',
          title: 'Offline-Daten werden geladen');
      expect(service.starts, 1);
    });

    test('bei zwei Melder-Sorten wird der Titel neutral', () async {
      // „Offline-Daten werden geladen" über einer laufenden Pilztour wäre
      // schlicht falsch.
      await coordinator.start('pilztour', 'Der Weg wird aufgezeichnet',
          title: 'Pilztour läuft', types: const {KeepAliveType.location});
      await coordinator.start('maps', 'Berlin — 10 %',
          title: 'Offline-Daten werden geladen');
      expect(service.titles.last, 'PilzBuddy arbeitet');

      // Und wieder eindeutig, sobald einer geht.
      await coordinator.stop('maps');
      expect(service.titles.last, 'Pilztour läuft');
    });
  });
}
