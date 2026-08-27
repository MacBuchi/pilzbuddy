import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_keep_alive_stub.dart'
    if (dart.library.io) 'download_keep_alive_service.dart';

/// Welchen Zweck ein Melder dem System gegenüber angibt (#338).
///
/// Android 14 verlangt, dass ein Foreground-Service seinen Typ nennt, und
/// prüft je Typ die passende Berechtigung. Ein Karten-Download ist
/// `dataSync`, eine laufende Pilztour ist `location` — und wer beides
/// gleichzeitig tut, braucht beides.
enum KeepAliveType {
  dataSync,
  location;
}

/// Hält den App-Prozess wach, solange eine Offline-Karte lädt oder eine
/// Pilztour aufzeichnet.
///
/// Ohne das friert Android den Prozess ein, sobald der Nutzer in eine andere
/// App wechselt: der Download läuft im Main-Isolate, und ein „cached"
/// Prozess wird ab Android 12 (bei manchen Herstellern deutlich früher)
/// eingefroren — Sockets und Timer stehen still. Verloren geht dabei nichts
/// (die `.part`-Datei bleibt, der nächste Versuch setzt per Range-Request
/// auf), aber der Fortschritt bleibt eben stehen.
///
/// Ein Foreground-Service mit sichtbarer Benachrichtigung hebt die
/// Prozess-Priorität an und nimmt ihn damit aus dem Freezer heraus.
abstract class DownloadKeepAlive {
  /// Startet den Service. Läuft er schon, werden nur Titel und Text
  /// aktualisiert — die Typen bleiben dann, wie sie waren; sie lassen
  /// sich an einem laufenden Service nicht ändern (siehe Koordinator).
  Future<void> start(String title, String text, Set<KeepAliveType> types);

  /// Aktualisiert Titel und Text der Benachrichtigung.
  Future<void> update(String title, String text);

  /// Schaltet den Wiederhol-Takt des Service-Isolates.
  ///
  /// `null` heißt „kein Takt" — der Zustand für Downloads, die im
  /// Main-Isolate laufen und den Service nur für die Prozess-Priorität
  /// brauchen. Eine Pilztour setzt hier ihren Messabstand: Ihre Arbeit
  /// passiert IM Service-Isolate, weil der das Wegwischen der App
  /// überlebt und der Main-Isolate nicht (#342).
  ///
  /// Anders als die Service-Typen lässt sich der Takt am laufenden
  /// Service ändern — `updateService` nimmt `foregroundTaskOptions`
  /// entgegen.
  Future<void> setRepeat(Duration? every);

  /// Beendet den Service. Muss auch nach Fehlern laufen.
  Future<void> stop();
}

/// Plattform-Implementierung: Foreground-Service auf Android, sonst nichts.
/// Tests überschreiben diesen Provider (siehe `test/fakes/test_app.dart`).
final downloadKeepAliveProvider =
    Provider<DownloadKeepAlive>((ref) => createDownloadKeepAlive());

/// Teilt den EINEN Foreground-Service unter mehreren Downloads auf.
///
/// Nötig seit dem Wald-Vorlauf (#264): Regionskarte und feines Waldgitter
/// können gleichzeitig laufen, und `stop()` des einen zog dem anderen den
/// Service unter den Füßen weg — also genau der eingefrorene Prozess,
/// gegen den er da ist. Gezählt wird über Schlüssel und nicht als bloße
/// Zahl, damit der Text sagen kann, was gerade läuft.
///
/// Kein `logError` und keine Fehlerbehandlung: Die dahinterliegende
/// Implementierung schluckt bereits alles — der Download ist wichtiger
/// als seine Benachrichtigung.
class DownloadKeepAliveCoordinator {
  DownloadKeepAliveCoordinator(this._keepAlive);

  final DownloadKeepAlive _keepAlive;

  /// Schlüssel → was der jeweilige Melder braucht, in Anmeldereihenfolge.
  final _needs = <String, ({String title, String text, Set<KeepAliveType> types})>{};

  /// Die Typen, mit denen der Service tatsächlich gestartet wurde.
  Set<KeepAliveType> _runningTypes = const {};

  /// Meldet einen Verbraucher an und startet den Service, falls er ruht.
  ///
  /// **Ändert sich dabei die Typmenge, wird der Service neu gestartet.**
  /// `updateService` kann die Typen nicht ändern (nachgesehen in
  /// flutter_foreground_task 10.0.0), und ein als `dataSync` laufender
  /// Service liefert einer Pilztour im Hintergrund keine Standorte mehr —
  /// Android 14 prüft je Typ. Die kurze Lücke beim Neustart ist der
  /// Preis; sie kostet höchstens einen Fix.
  Future<void> start(
    String key,
    String text, {
    required String title,
    Set<KeepAliveType> types = const {KeepAliveType.dataSync},
  }) async {
    _needs[key] = (title: title, text: text, types: types);
    final wanted = _wantedTypes();
    if (_runningTypes.isNotEmpty && !_sameTypes(_runningTypes, wanted)) {
      await _keepAlive.stop();
      _runningTypes = const {};
    }
    _runningTypes = wanted;
    await _keepAlive.start(_title(), _combined(), wanted);
  }

  /// Neuer Text dieses Melders. Unbekannte Schlüssel und unveränderte
  /// Texte tun nichts — sonst schickte jeder einzelne Chunk eine
  /// Aktualisierung über den Platform-Channel.
  Future<void> update(String key, String text) async {
    final need = _needs[key];
    if (need == null || need.text == text) return;
    _needs[key] = (title: need.title, text: text, types: need.types);
    await _keepAlive.update(_title(), _combined());
  }

  /// Meldet einen Verbraucher ab. Der Service endet erst, wenn der letzte
  /// gegangen ist.
  Future<void> stop(String key) async {
    if (_needs.remove(key) == null) return;
    if (_needs.isEmpty) {
      await _keepAlive.stop();
      _runningTypes = const {};
      return;
    }
    await _keepAlive.update(_title(), _combined());
  }

  /// Reicht den Wiederhol-Takt an den Service durch (#342).
  ///
  /// Bewusst NICHT je Melder gezählt wie Texte und Typen: Der Takt gehört
  /// dem Service-Isolate, und es gibt genau einen Verbraucher, der ihn
  /// braucht. Ein zweiter mit anderem Takt wäre eine Frage ohne Antwort —
  /// dann gehört hier eine Buchführung hin, keine stille Überschreibung.
  Future<void> setRepeat(Duration? every) => _keepAlive.setRepeat(every);

  /// Läuft gerade irgendein Verbraucher? (Für Aufrufer, die nur wissen
  /// wollen, ob sie den Service noch brauchen.)
  bool get isEmpty => _needs.isEmpty;

  Set<KeepAliveType> _wantedTypes() =>
      {for (final need in _needs.values) ...need.types};

  static bool _sameTypes(Set<KeepAliveType> a, Set<KeepAliveType> b) =>
      a.length == b.length && a.containsAll(b);

  /// Bei genau einem Melder sein eigener Titel, sonst ein neutraler —
  /// „Offline-Daten werden geladen" über einer laufenden Pilztour wäre
  /// schlicht falsch.
  String _title() => _needs.length == 1
      ? _needs.values.single.title
      : 'PilzBuddy arbeitet';

  String _combined() => [for (final need in _needs.values) need.text].join(' · ');
}

/// Der Koordinator lebt so lange wie der ProviderScope — er ist die
/// gemeinsame Buchführung aller Verbraucher.
final downloadKeepAliveCoordinatorProvider =
    Provider<DownloadKeepAliveCoordinator>(
        (ref) => DownloadKeepAliveCoordinator(
            ref.watch(downloadKeepAliveProvider)));
