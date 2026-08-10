// Die Warteschlange auf der Platte (#267).
//
// Gegen ein Temp-Verzeichnis, kein Netz: Was hier geprüft wird, ist der
// Unterschied zwischen „der Fund ist gesichert" und „der Fund ist weg".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/outbox.dart';
import 'package:pilzbuddy/data/spot_repository.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('outbox_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  NewSpotJob spotJob({String id = 'job-1', String? name = 'Buchenhang'}) =>
      NewSpotJob(
        id: id,
        createdAt: DateTime.utc(2026, 8, 10, 9),
        lat: 51.1,
        lng: 10.4,
        name: name,
        finds: [
          NewFind(
              species: 'Steinpilz',
              count: 3,
              foundOn: DateTime.utc(2026, 8, 10),
              clientId: '$id-f1'),
          NewFind.blank(
              foundOn: DateTime.utc(2026, 8, 10), clientId: '$id-f2'),
        ],
      );

  NewFindsJob findsJob({
    String id = 'job-2',
    String spotId = 'spot-7',
    bool spotIsPending = false,
  }) =>
      NewFindsJob(
        id: id,
        createdAt: DateTime.utc(2026, 8, 10, 10),
        spotId: spotId,
        spotIsPending: spotIsPending,
        finds: [
          NewFind(
              species: 'Pfifferling',
              foundOn: DateTime.utc(2026, 8, 10),
              clientId: '$id-f1'),
        ],
      );

  test('ein Auftrag übersteht das Schreiben und Lesen unverändert',
      () async {
    final outbox = FileOutbox(baseDirOverride: dir);
    await outbox.append(spotJob(), uid: 'me');
    await outbox.append(findsJob(spotIsPending: true, spotId: 'job-1'),
        uid: 'me');

    // Frische Instanz: Es geht um die Datei, nicht um den Speicher.
    final jobs = await FileOutbox(baseDirOverride: dir).read(uid: 'me');
    expect(jobs, hasLength(2));

    final spot = jobs.first as NewSpotJob;
    expect(spot.id, 'job-1');
    expect(spot.name, 'Buchenhang');
    expect(spot.lat, closeTo(51.1, 1e-9));
    expect(spot.finds, hasLength(2));
    expect(spot.finds.first.species, 'Steinpilz');
    expect(spot.finds.first.count, 3);
    expect(spot.finds.first.clientId, 'job-1-f1');
    expect(spot.finds.last.blank, isTrue,
        reason: 'ein Leergang muss als solcher wiederkommen — sonst zählte '
            'er nach dem Neustart als Fund');
    expect(spot.finds.last.species, isNull);

    final finds = jobs.last as NewFindsJob;
    expect(finds.spotId, 'job-1');
    expect(finds.spotIsPending, isTrue,
        reason: 'ohne dieses Flag wäre die Kennung eine Server-id, und der '
            'Fund landete am falschen Ort');
  });

  test('ein fremdes Konto sieht nichts', () async {
    // Die Aufträge eines anderen Nutzers dürfen niemals in einer fremden
    // Sitzung hochgehen — sie trügen dessen Fundstellen in mein Konto.
    final outbox = FileOutbox(baseDirOverride: dir);
    await outbox.append(spotJob(), uid: 'me');
    expect(await outbox.read(uid: 'someone-else'), isEmpty);
    expect(await outbox.read(uid: 'me'), hasLength(1));
  });

  test('eine unlesbare Datei heißt „kein Korb", nicht Absturz', () async {
    final file = File('${dir.path}/${FileOutbox.dirName}/jobs.json');
    file.createSync(recursive: true);
    file.writeAsStringSync('{kaputt');
    expect(await FileOutbox(baseDirOverride: dir).read(uid: 'me'), isEmpty);
  });

  test('ein unbekannter Auftragstyp wird übersprungen, der Rest bleibt',
      () async {
    // Eine ältere App liest den Korb einer neueren: Was sie nicht kennt,
    // darf sie nicht mitreißen.
    final outbox = FileOutbox(baseDirOverride: dir);
    await outbox.append(spotJob(), uid: 'me');
    final file = File('${dir.path}/${FileOutbox.dirName}/jobs.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    json['jobs'] = [
      {'kind': 'teleport', 'id': 'x', 'created_at': '2026-08-10T09:00:00Z'},
      ...json['jobs'] as List<dynamic>,
    ];
    file.writeAsStringSync(jsonEncode(json));

    final jobs = await outbox.read(uid: 'me');
    expect(jobs, hasLength(1));
    expect(jobs.single, isA<NewSpotJob>());
  });

  test('ein Auftrag mit unlesbarem Eintrag fällt ganz weg', () async {
    // Halb wäre schlimmer als gar nicht: Ein Spot mit zwei statt drei
    // Funden sieht vollständig aus und ist es nicht.
    final outbox = FileOutbox(baseDirOverride: dir);
    await outbox.append(spotJob(), uid: 'me');
    final file = File('${dir.path}/${FileOutbox.dirName}/jobs.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    ((json['jobs'] as List).first as Map)['finds'][1]['found_on'] = 'kein Datum';
    file.writeAsStringSync(jsonEncode(json));

    expect(await outbox.read(uid: 'me'), isEmpty);
  });

  test('ein Eintrag ohne Kennung macht den Auftrag ungültig', () async {
    // Ohne client_id wäre die Wiedervorlage nicht wiederholbar — also
    // genau das nicht, wofür der Korb da ist.
    final file = File('${dir.path}/${FileOutbox.dirName}/jobs.json');
    file.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({
      'uid': 'me',
      'jobs': [
        {
          'kind': 'finds',
          'id': 'job-9',
          'created_at': '2026-08-10T09:00:00Z',
          'spot_id': 'spot-1',
          'finds': [
            {'species': 'Steinpilz', 'found_on': '2026-08-10'},
          ],
        },
      ],
    }));
    expect(await FileOutbox(baseDirOverride: dir).read(uid: 'me'), isEmpty);
  });

  test('replaceAll ersetzt den ganzen Stand', () async {
    final outbox = FileOutbox(baseDirOverride: dir);
    await outbox.append(spotJob(), uid: 'me');
    await outbox.append(findsJob(), uid: 'me');

    await outbox.replaceAll([findsJob(id: 'job-3')], uid: 'me');
    final jobs = await outbox.read(uid: 'me');
    expect(jobs, hasLength(1));
    expect(jobs.single.id, 'job-3');
  });

  test('Schreibfehler werden NICHT geschluckt', () async {
    // Der Unterschied zum Zwischenspeicher, und der wichtigste Satz
    // dieser Datei: Liegt der Auftrag nicht, ist der Fund weg — das muss
    // der Aufrufer erfahren.
    final blocked = Directory('${dir.path}/blocked');
    blocked.createSync();
    // Eine DATEI dort, wo das Verzeichnis hin soll: Das Anlegen scheitert.
    File('${blocked.path}/${FileOutbox.dirName}').createSync();

    final outbox = FileOutbox(baseDirOverride: blocked);
    await expectLater(
        outbox.append(spotJob(), uid: 'me'), throwsA(isA<Object>()));
  });

  test('gleichzeitige Anhänge gehen nicht verloren', () async {
    // Der reale Fall: Die Wiedervorlage schreibt den Korb neu, während
    // die Nutzerin einen weiteren Fund einträgt.
    final outbox = FileOutbox(baseDirOverride: dir);
    await Future.wait([
      for (var i = 0; i < 5; i++)
        outbox.append(spotJob(id: 'job-$i'), uid: 'me'),
    ]);
    final jobs = await outbox.read(uid: 'me');
    expect(jobs.map((j) => j.id).toSet(), hasLength(5));
  });

  test('nach einem Schreibfehler nimmt der Korb weiter Aufträge an',
      () async {
    // Sonst stünde er nach dem ersten Fehlschlag für immer — die Kette
    // darf nicht an einem Fehler abreißen.
    final outbox = FileOutbox(baseDirOverride: dir);
    final file = Directory('${dir.path}/${FileOutbox.dirName}');
    file.createSync(recursive: true);
    // Verzeichnis statt Datei: Das Umbenennen der .part scheitert.
    Directory('${file.path}/jobs.json').createSync();
    await expectLater(
        outbox.append(spotJob(), uid: 'me'), throwsA(isA<Object>()));

    Directory('${file.path}/jobs.json').deleteSync();
    await outbox.append(spotJob(id: 'job-danach'), uid: 'me');
    expect((await outbox.read(uid: 'me')).single.id, 'job-danach');
  });

  test('newClientId liefert eine gültige, jedes Mal andere UUID v4', () {
    final ids = {for (var i = 0; i < 200; i++) newClientId()};
    expect(ids, hasLength(200), reason: 'zwei gleiche Kennungen wären zwei '
        'Aufträge, von denen einer verschwindet');
    final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    for (final id in ids) {
      expect(pattern.hasMatch(id), isTrue,
          reason: '$id muss als uuid durchgehen — die Spalte ist uuid');
    }
  });
}
