// TEMPORÄR — Absturzsuche in der Vektor-Karte. NICHT AUSLIEFERN.
//
// Warum diese Datei existiert: Abstürze hinterlassen bei uns nichts.
// `error_reports` erfasst nur Fehler, die die App überlebt, und Android
// Vitals sieht ausschließlich Play-Installationen — die es noch nicht gibt
// (#108). Ein Absturz beim Bedienen der Karte ist damit unsichtbar, und
// unterhalb von Dart (natives SIGSEGV, Kill durch Speicherdruck) fängt ihn
// auch kein Dart-Handler.
//
// Sentry überbrückt genau diese Lücke, bis Android Vitals übernimmt. Es
// gehört NICHT in einen veröffentlichten Release: #111 hat einen
// Absturzdienst bewusst abgelehnt (laufende Kosten, weiterer
// Auftragsverarbeiter in der Datenschutzerklärung), und jeder Versions-Bump
// auf `main` veröffentlicht die APK öffentlich.
//
// Zwei Sicherungen dagegen:
//  1. Ohne `--dart-define=SENTRY_DSN=…` passiert hier NICHTS — die App läuft
//     exakt wie ohne diese Datei. Ein versehentlicher Build ohne die Angabe
//     schickt also nichts.
//  2. `test/no_sentry_in_release_test.dart` schlägt an, sobald `pubspec.yaml`
//     die Abhängigkeit trägt und gleichzeitig eine Version gebaut werden
//     soll — der Ausbau lässt sich nicht vergessen.
//
// Bauen:
//   flutter build apk --release --dart-define=SENTRY_DSN=https://…
// Ausbauen: diese Datei löschen, den Block in main.dart entfernen,
//   `flutter pub remove sentry_flutter`.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Die DSN kommt aus dem Build-Aufruf, nicht aus dem Repo: Das Repo ist
/// öffentlich, und eine DSN ist ein Schreibschlüssel — im Klartext
/// eingecheckt könnte jeder das Projekt mit Müll fluten.
const _dsn = String.fromEnvironment('SENTRY_DSN');

bool get sentryEnabled => _dsn.isNotEmpty;

/// Startet die App mit Sentry, falls eine DSN mitgegeben wurde — sonst
/// unverändert über [runner].
Future<void> runWithCrashHunt(void Function() runner) async {
  if (!sentryEnabled) {
    runner();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _dsn;
      // Nur Abstürze, keine Performance-Daten: Wir suchen einen Absturz und
      // nicht Ladezeiten, und weniger Datenverkehr heißt weniger Einfluss
      // auf genau das Verhalten, das wir beobachten wollen.
      options.tracesSampleRate = 0;
      // Android-ANRs mitnehmen: „App reagiert nicht" beim Bedienen der
      // Karte sieht für den Nutzer wie ein Absturz aus und wäre sonst eine
      // andere Ursache mit demselben Symptom.
      options.anrEnabled = true;
      // NIEMALS Screenshots oder Widget-Baum: Auf der Karte stehen
      // Pilz-Fundorte. Ein Absturzbericht darf keine Koordinaten
      // mitschicken.
      options.attachScreenshot = false;
      // attachViewHierarchy ist experimentell und bleibt deshalb ungesetzt
      // — der Standard schickt ihn ohnehin nicht.
      options.sendDefaultPii = false;
      options.environment = 'crash-hunt';
    },
    appRunner: runner,
  );
}

/// Beobachtet die Provider, die für den Absturz interessant sind, und legt
/// ihre Wechsel als Sentry-Breadcrumbs ab.
///
/// Bewusst als [ProviderObserver] und nicht als Aufrufe im Karten-Code:
/// So bleibt der Feature-Code frei von Sentry, und der Ausbau ist ein
/// Löschen. Ohne diese Spur sagt ein Stacktrace nur *wo* es knallte, nicht
/// *in welchem Kartenmodus* — und genau das ist die Frage.
class CrashHuntObserver extends ProviderObserver {
  const CrashHuntObserver();

  /// Provider, deren Name im Breadcrumb landen soll. Alles andere wäre
  /// Rauschen: Bei jedem Positions-Tick eine Spur zu schreiben verdrängt
  /// die interessanten aus dem Puffer.
  static const _watched = {
    'offlineMapStyleProvider',
    'baseMapStyleProvider',
    'noConnectivityProvider',
    'installedMapsProvider',
    'offlineMapEnabledProvider',
  };

  void _crumb(String name, String message) {
    if (!sentryEnabled) return;
    Sentry.addBreadcrumb(Breadcrumb(
      category: 'karte',
      message: '$name: $message',
      level: SentryLevel.info,
    ));
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    final name = provider.name ?? provider.runtimeType.toString();
    if (!_watched.any(name.contains)) return;
    _crumb(name, '${_describe(previousValue)} → ${_describe(newValue)}');
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    // Ein gescheiterter Provider kurz vor dem Absturz ist die halbe Spur.
    _crumb(provider.name ?? provider.runtimeType.toString(),
        'Fehler: ${error.runtimeType}');
  }

  /// Nur Art und Vorhandensein, nie den Inhalt: Ein `AsyncValue<List<Spot>>`
  /// ausgeschrieben stünden Koordinaten im Absturzbericht.
  String _describe(Object? value) => switch (value) {
        null => 'null',
        AsyncLoading() => 'lädt',
        AsyncError() => 'Fehler',
        AsyncData(:final value) => value == null ? 'da, leer' : 'da',
        bool() => value.toString(),
        _ => value.runtimeType.toString(),
      };
}
