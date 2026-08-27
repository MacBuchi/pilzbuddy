// Die Pilztour im Isolate des Foreground-Service (#342).
//
// **Warum überhaupt hier und nicht im Main-Isolate.** Die erste Fassung
// (1.102.0) maß auf einem `Timer.periodic` im Main-Isolate. Das ist genau
// so weit richtig, wie die App lebt: Wischt der Nutzer sie aus der
// Übersicht, stirbt der Flutter-Prozess samt allen Dart-Timern — der
// Service läuft sichtbar weiter (`START_STICKY`, kein `stopWithTask`),
// und aufgezeichnet wird trotzdem nichts. Genau so am 2026-08-27 im Feld
// gesehen: „Solange die App aktiv ist, wird sie geschlossen, wird nichts
// aufgezeichnet, obwohl der Hintergrundservice aktiv ist."
//
// `flutter_foreground_task` startet für den Service ein EIGENES
// Flutter-Isolate, das das Wegwischen überlebt. Was hier steht, läuft
// dort — und nur dort.
//
// **Was in diesem Isolate NICHT gilt:** kein Riverpod, kein
// `ProviderScope`, keine Widgets, kein `logError` mit Sink (der hängt an
// `main()`). Alles, was hier gebraucht wird, muss über
// `FlutterForegroundTask.saveData` von drüben herübergereicht oder aus
// der Datei gelesen werden.
//
// **Warum der Pfad herübergereicht wird und nicht `path_provider`:**
// Plugins werden im Hintergrund-Engine zwar registriert
// (`FlutterEngine(context)` registriert automatisch), aber der Pfad ist
// eine Konstante des Geräts — ihn einmal drüben aufzulösen ist billiger
// und hat eine Fehlerquelle weniger als ein Kanalaufruf je Takt.
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'tour_store.dart';
import 'tour_track.dart';

/// Schlüssel der Brücke zwischen den Isolaten (SharedPreferences).
///
/// Bewusst flache Werte: `saveData` nimmt nur int, double, String und
/// bool an.
const kTourDataDir = 'tour_dir';
const kTourDataUid = 'tour_uid';
const kTourDataActive = 'tour_active';

/// Ein Punkt, den der Service gemessen hat — als Zeichenkette an den
/// Main-Isolate, weil `sendDataToMain` nur einfache Werte trägt.
String encodeTourTick(TourPoint point) =>
    '${point.lat};${point.lng};${point.at.toUtc().toIso8601String()};'
    '${point.accuracyM}';

TourPoint? decodeTourTick(Object? data) {
  if (data is! String) return null;
  final parts = data.split(';');
  if (parts.length != 4) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  final at = DateTime.tryParse(parts[2]);
  final accuracy = double.tryParse(parts[3]);
  if (lat == null || lng == null || at == null || accuracy == null) {
    return null;
  }
  return TourPoint(
      lat: lat, lng: lng, at: at.toUtc(), accuracyM: accuracy);
}

/// Ein Takt der Aufzeichnung: messen, anhängen, melden.
///
/// Gibt zurück, was gemessen wurde — `null`, wenn gerade keine Tour läuft
/// oder kein Fix zustande kam. **Wirft nie**: Eine Ausnahme in diesem
/// Isolate hat niemanden, der sie fängt, und würde die Aufzeichnung für
/// den Rest der Tour beenden.
Future<TourPoint?> recordTourTick({
  Future<Position?> Function()? fix,
  TourStore Function(String dir)? storeFor,
}) async {
  try {
    final active =
        await FlutterForegroundTask.getData<bool>(key: kTourDataActive);
    if (active != true) return null;
    final dir =
        await FlutterForegroundTask.getData<String>(key: kTourDataDir);
    if (dir == null) return null;

    final position = await (fix ?? _fix)();
    if (position == null) return null;
    final point = TourPoint(
      lat: position.latitude,
      lng: position.longitude,
      at: position.timestamp.toUtc(),
      accuracyM: position.accuracy,
    );

    final store = (storeFor ?? _storeFor)(dir);
    await store.appendPoint(point);
    // Damit die Karte mitläuft, solange jemand hinsieht. Ist die App weg,
    // geht das ins Leere — und genau dann trägt die Datei allein.
    FlutterForegroundTask.sendDataToMain(encodeTourTick(point));
    return point;
  } catch (_) {
    return null;
  }
}

TourStore _storeFor(String dir) => FileTourStore(baseDir: Directory(dir));

Future<Position?> _fix() async {
  try {
    // KEIN `timeLimit`: Die erste Fassung setzte 20 s und machte damit
    // aus jedem langsamen Hintergrund-Fix stillschweigend gar keinen.
    // Ein Takt, der einmal überlappt, ist harmloser als eine Reihe, die
    // nur im Vordergrund Werte hat.
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high),
    );
  } catch (_) {
    // Kein Empfang zum Himmel, Dienst aus: ein fehlender Fix ist keine
    // Ausnahme, sondern der Wald.
    return null;
  }
}

/// Der Task-Handler des geteilten Service.
///
/// Er trägt beide Nutzer: Für einen Download tut er nichts (der läuft im
/// Main-Isolate und braucht nur die Prozess-Priorität), für eine Pilztour
/// misst er. Welcher Fall gilt, steht in der Brücke — ein zweiter
/// Handler ginge nicht, weil der Service genau einen Einstiegspunkt hat.
class ServiceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Bewusst nicht abgewartet: `onRepeatEvent` ist synchron, und der
    // nächste Takt kommt erst nach dem eingestellten Abstand.
    recordTourTick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
