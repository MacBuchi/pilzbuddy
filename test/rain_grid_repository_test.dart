// Was das Regen-Repository auf Platte anstellt.
//
// Der Netzweg braucht kein eigenes Netz — beide Provider sind im Harness
// überschrieben, und die Fehlerpfade degradieren still. Geprüft wird
// hier, was NICHT still degradiert, sondern still FALSCH wäre: eine
// Fläche, die als Datei liegen bleibt, obwohl die App sie inzwischen
// anders zeichnet.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('rain_repo_test');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  RainGridRepository repo({http.Client? client}) =>
      RainGridRepository(baseDirOverride: base, client: client);

  final measured = DateTime.utc(2026, 8, 4, 5, 50);

  test('legt die Fläche als Datei ab und nennt ihre URL', () async {
    final url = await repo().writeFill('w4', measured, [1, 2, 3]);

    expect(url, isNotNull);
    expect(url, startsWith('file://'));
    final file = File(url!.substring('file://'.length));
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(file.path, contains('2026-08-04'),
        reason: 'ohne Messzeitpunkt im Namen läge ein neuer Stand unter '
            'derselben URL, und die Engine behielte das alte Bild');
  });

  test('schreibt auch dann, wenn die Datei schon liegt', () async {
    // Der Name kennt den Messzeitpunkt, nicht die Darstellung. Ohne
    // dieses Überschreiben bliebe nach einer App-Version mit anderen
    // Farben, anderer Deckkraft oder anderer Glättung das ALTE Bild
    // liegen — bis zur nächsten Messung. Genau das ist am 2026-08-04 am
    // Emulator passiert: pixelgleiches Ergebnis trotz geändertem Code.
    await repo().writeFill('w4', measured, [1, 2, 3]);
    final url = await repo().writeFill('w4', measured, [9, 9]);

    expect(await File(url!.substring('file://'.length)).readAsBytes(), [9, 9]);
  });

  test('räumt ältere Flächen weg, lässt Gitter und Manifest stehen',
      () async {
    // Gitter (`w4_…`) und Flächen (`fill_w4_…`) liegen im selben Ordner.
    // Ein Aufräumen, das seinen Namensanfang aus der Datei rät, die es
    // behalten will, reißt die jeweils andere Sorte mit.
    final dir = Directory('${base.path}/rain')..createSync(recursive: true);
    File('${dir.path}/w4_2026-08-03T05-50-00-000Z.bin.gz')
        .writeAsBytesSync([0]);
    File('${dir.path}/w4.json').writeAsStringSync('{}');
    await repo().writeFill('w4', DateTime.utc(2026, 8, 3), [1]);

    await repo().writeFill('w4', measured, [2]);

    final left = dir.listSync().map((e) => e.path.split('/').last).toSet();
    expect(left, {
      'w4_2026-08-03T05-50-00-000Z.bin.gz',
      'w4.json',
      'fill_w4_2026-08-04T05-50-00-000Z.png',
    });
  });

  test('trennt die Ebenen — eine neue 30-Tage-Fläche rührt die '
      '24-Stunden-Fläche nicht an', () async {
    await repo().writeFill('sf', measured, [1]);
    await repo().writeFill('w4', measured, [2]);

    final dir = Directory('${base.path}/rain');
    expect(dir.listSync().length, 2);
  });

  group('loadWeatherTable', () {
    final goodBytes = GZipEncoder().encode(utf8.encode('{"days":[]}'))!;
    const manifest =
        '{"weather": {"file": "weather_stations.json.gz", '
        '"days": ["2026-07-21", "2026-08-03"]}}';

    http.Client serving({List<int>? asset, String? manifestBody}) =>
        MockClient((request) async {
          if (request.url.path.endsWith('rain_manifest.json')) {
            return http.Response(manifestBody ?? manifest, 200);
          }
          if (request.url.path.endsWith('weather_stations.json.gz')) {
            return http.Response.bytes(asset ?? goodBytes, 200);
          }
          return http.Response('nicht da', 404);
        });

    Directory dir() => Directory('${base.path}/rain');
    List<String> onDisk() => dir()
        .listSync()
        .map((e) => e.path.split('/').last)
        .toList()
      ..sort();

    test('lädt, legt unter dem jüngsten Tag ab und räumt Ältere weg',
        () async {
      dir().createSync(recursive: true);
      File('${dir().path}/weather_2026-08-01.json.gz').writeAsBytesSync([1]);
      // Ein Tagesstapel-Nachbar im selben Ordner: Das Aufräumen darf nur
      // die eigene Sorte anfassen.
      File('${dir().path}/rain_day_2026-08-01.bin.gz').writeAsBytesSync([2]);

      final bytes = await repo(client: serving()).loadWeatherTable();

      expect(bytes, goodBytes);
      expect(onDisk(),
          ['rain_day_2026-08-01.bin.gz', 'weather_2026-08-03.json.gz'],
          reason: 'der alte Stand muss weg, der Nachbar bleiben');
    });

    test('nimmt den Zwischenspeicher, statt neu zu laden', () async {
      dir().createSync(recursive: true);
      File('${dir().path}/weather_2026-08-03.json.gz')
          .writeAsBytesSync([7, 7, 7]);

      final bytes = await repo(client: serving()).loadWeatherTable();

      expect(bytes, [7, 7, 7],
          reason: 'derselbe Stand liegt schon da — 45 KB je Blattöffnung '
              'wären der Preis');
    });

    test('ohne Netz kommt der jüngste Stand von der Platte', () async {
      dir().createSync(recursive: true);
      File('${dir().path}/weather_2026-08-01.json.gz').writeAsBytesSync([1]);
      File('${dir().path}/weather_2026-08-02.json.gz').writeAsBytesSync([2]);
      final offline = MockClient((_) async => throw const SocketException(''));

      expect(await repo(client: offline).loadWeatherTable(), [2]);
    });

    test('ein Download, der sich nicht auspacken lässt, wird nicht '
        'abgelegt', () async {
      // Sonst vergiftete ein abgebrochener Download jeden weiteren
      // Versuch bis zum nächsten Tabellenstand.
      dir().createSync(recursive: true);
      File('${dir().path}/weather_2026-08-01.json.gz').writeAsBytesSync([1]);

      final bytes = await repo(client: serving(asset: [9, 9, 9]))
          .loadWeatherTable();

      expect(bytes, [1], reason: 'der letzte gute Stand ist die Antwort');
      expect(onDisk(), ['weather_2026-08-01.json.gz'],
          reason: 'der kaputte Download darf nicht liegen bleiben');
    });

    test('ohne Netz und ohne Platte gibt es nichts — still', () async {
      final offline = MockClient((_) async => throw const SocketException(''));
      expect(await repo(client: offline).loadWeatherTable(), isNull);
    });
  });

  // Der Weg ohne Platte — das ist die Web-App.
  //
  // Bis 1.111.0 gab es ihn nicht, und das fiel niemandem auf, weil er
  // still scheiterte: ohne Gitter zeichnet die Karte das harte DWD-Bild
  // statt der eigenen Fläche, und die Ampel stand ohne Regendaten da
  // (#365, #366). Zwei Sperren lagen hintereinander — CORS auf den
  // Release-Anhängen und `path_provider`, das es im Browser nicht gibt.
  // Diese Gruppe hält die zweite fest; die erste steht in
  // `rainDataWebBaseUrl` und im Workflow.
  group('ohne Platte', () {
    RainGridRepository webRepo({http.Client? client}) => RainGridRepository(
          baseDirOverride: base,
          client: client,
          cachesToDisk: false,
        );

    Directory dir() => Directory('${base.path}/rain');
    bool wroteAnything() => dir().existsSync() && dir().listSync().isNotEmpty;

    final gridBytes = GZipEncoder().encode(<int>[3, 0, 0, 0])!;
    const gridManifest = '{"layers": {"w4": {"layer": "w4", '
        '"file": "w4_20260804.bin.gz", "width": 2, "height": 2, '
        '"west": 5.0, "east": 16.0, "north": 55.0, "south": 47.0, '
        '"measured": "2026-08-04T05:50:00Z"}}}';

    test('holt das Gitter und legt nichts ab', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('rain_manifest.json')) {
          return http.Response(gridManifest, 200);
        }
        return http.Response.bytes(gridBytes, 200);
      });

      final grid = await webRepo(client: client).load('w4');

      expect(grid, isNotNull, reason: 'ohne Gitter keine eigene Fläche und '
          'keine Ampel — genau der gemeldete Fehler');
      expect(grid!.width, 2);
      expect(wroteAnything(), isFalse,
          reason: 'im Browser gibt es keine Platte; ein Schreibversuch '
              'würde werfen, und der Fehler wäre wieder still');
    });

    test('holt die Stationstabelle und legt nichts ab', () async {
      final table = GZipEncoder().encode(utf8.encode('{"days":[]}'))!;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('rain_manifest.json')) {
          return http.Response(
              '{"weather": {"file": "weather_stations.json.gz", '
              '"days": ["2026-08-03"]}}',
              200);
        }
        return http.Response.bytes(table, 200);
      });

      expect(await webRepo(client: client).loadWeatherTable(), table);
      expect(wroteAnything(), isFalse);
    });

    test('holt den Tagesstapel und legt nichts ab', () async {
      final day = GZipEncoder().encode(<int>[1, 0, 0, 0])!;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('rain_manifest.json')) {
          return http.Response(
              '{"daily": {"width": 2, "height": 2, "west": 5.0, '
              '"east": 16.0, "north": 55.0, "south": 47.0, "days": ['
              '{"date": "2026-08-29T00:00:00Z", '
              '"file": "rain_day_20260829.bin.gz"}]}}',
              200);
        }
        return http.Response.bytes(day, 200);
      });

      final stack = await webRepo(client: client).loadDailyStack();

      expect(stack, isNotNull);
      expect(stack!.days, hasLength(1));
      expect(wroteAnything(), isFalse);
    });

    test('die Fläche wird nicht geschrieben, sondern abgelehnt', () async {
      // `writeFill` liefert eine `file://`-URL für MapLibre. Die Engine
      // gibt es im Browser nicht — dort nimmt flutter_map dieselben
      // Bytes direkt als `MemoryImage`.
      expect(await webRepo().writeFill('w4', measured, [1, 2, 3]), isNull);
      expect(wroteAnything(), isFalse);
    });

    test('ohne Netz gibt es nichts — still, und ohne auf Platte zu sehen',
        () async {
      final offline = MockClient((_) async => throw const SocketException(''));

      expect(await webRepo(client: offline).load('w4'), isNull);
      expect(await webRepo(client: offline).loadWeatherTable(), isNull);
      expect(await webRepo(client: offline).loadDailyStack(), isNull);
    });
  });

  group('die Adresse für den Browser', () {
    test('zeigt nicht auf die Release-Anhänge', () {
      // Gemessen am 2026-09-02: `github.com/…/releases/download/…`
      // schickt keinen `access-control-allow-origin`-Header, auch nicht
      // über die API — deren 302 trägt CORS, das Ziel
      // `release-assets.githubusercontent.com` nicht, und der Browser
      // prüft am Ende der Weiterleitung. Wer hier zurückdreht, holt
      // #365 und #366 zurück.
      expect(rainDataWebBaseUrl, isNot(contains('releases/download')));
      expect(rainDataWebBaseUrl, startsWith('https://raw.githubusercontent.com/'));
    });

    test('ihr Branch heißt nicht wie der Tag', () {
      // In einer raw-URL steht nur ein Name. Hießen Tag und Branch
      // gleich, entschiede der Dienst, welchen er ausliefert — der
      // Spiegel wäre ein Zufall.
      final branch = rainDataWebBaseUrl.split('/').last;
      final tag = rainDataBaseUrl.split('/').last;
      expect(branch, isNot(tag));
    });

    test('der Workflow spiegelt in genau diesen Branch', () {
      // Zwei Seiten, die still auseinanderlaufen können: Dart holt von
      // einem Branch, den ein Workflow schreibt. Stimmt der Name nicht
      // überein, liefert raw einen 404 — und die App fällt still auf
      // das DWD-Bild zurück, also genau in den gemeldeten Fehler.
      final yaml = File('.github/workflows/rain-data.yml').readAsStringSync();
      final branch = rainDataWebBaseUrl.split('/').last;

      expect(yaml, contains('--orphan $branch'),
          reason: 'der Workflow muss den Branch bauen, den die App liest');
      expect(yaml, contains('git push -q --force'),
          reason: 'ohne force wüchse die Historie um mehrmals täglich 2 MB');
    });
  });
}
