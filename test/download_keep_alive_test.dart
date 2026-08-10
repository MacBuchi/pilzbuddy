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
    await coordinator.start('maps', 'Berlin — 10 %');
    await coordinator.start('forest', 'Feine Waldkarte — 0 %');

    expect(service.running, isTrue);
    expect(service.starts, 1, reason: 'nicht zwei Services nebeneinander');
  });

  test('der Service endet erst, wenn der letzte gegangen ist', () async {
    await coordinator.start('maps', 'Berlin — 10 %');
    await coordinator.start('forest', 'Feine Waldkarte — 0 %');

    await coordinator.stop('maps');
    expect(service.running, isTrue,
        reason: 'der Wald-Vorlauf läuft noch — sein Prozess darf nicht '
            'eingefroren werden');

    await coordinator.stop('forest');
    expect(service.running, isFalse,
        reason: 'eine Dauerbenachrichtigung wäre grob unhöflich');
  });

  test('der Text nennt, was gerade läuft', () async {
    await coordinator.start('maps', 'Berlin — 10 %');
    await coordinator.start('forest', 'Feine Waldkarte — 0 %');
    expect(service.texts.last, contains('Berlin'));
    expect(service.texts.last, contains('Waldkarte'));

    // Nach dem Abmelden verschwindet der Melder auch aus dem Text.
    await coordinator.stop('maps');
    expect(service.texts.last, isNot(contains('Berlin')));
    expect(service.texts.last, contains('Waldkarte'));
  });

  test('unveränderter Text geht nicht über den Kanal', () async {
    // Sonst schickte jeder einzelne Chunk eine Aktualisierung.
    await coordinator.start('maps', 'Berlin — 10 %');
    final before = service.texts.length;
    await coordinator.update('maps', 'Berlin — 10 %');
    expect(service.texts, hasLength(before));

    await coordinator.update('maps', 'Berlin — 11 %');
    expect(service.texts, hasLength(before + 1));
  });

  test('ein unbekannter Schlüssel tut nichts', () async {
    await coordinator.start('maps', 'Berlin — 10 %');

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
    await coordinator.start('maps', 'Berlin — 10 %');
    await coordinator.stop('maps');
    expect(service.running, isFalse);

    await coordinator.start('forest', 'Feine Waldkarte — 0 %');
    await coordinator.stop('maps');
    expect(service.running, isTrue,
        reason: 'der zweite Abmeldeversuch gehört einem Melder, der weg ist');
  });
}
