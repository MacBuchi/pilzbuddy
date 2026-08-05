import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/errors.dart';
import 'core/map_data_license.dart';
import 'core/settings.dart';
import 'core/supabase_config.dart';
import 'core/tile_memory.dart';
import 'data/error_report_repository.dart';
import 'data/exit_info_repository.dart';
import 'data/exit_reporting.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Vor dem ersten Frame: sonst füllt sich der Bild-Cache noch mit der
  // großzügigen Vorgabe (siehe lib/core/tile_memory.dart, Issue #142).
  applyTileImageBudget(
      binding.platformDispatcher.views.firstOrNull?.physicalSize);
  registerMapDataLicense();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  final reports = ErrorReportRepository(Supabase.instance.client);
  // Absichtlich ohne await: das Melden darf den Programmfluss weder
  // aufhalten noch scheitern lassen. Fehler beim Melden werden geschluckt —
  // sie hier zu loggen wäre eine Endlosschleife.
  setErrorSink((context, error, stackTrace) {
    reports.report(context, error, stackTrace).catchError((Object _) {});
  });

  // Auch nicht gefangene Fehler melden. Android Vitals sieht davon nur die
  // Play-Installationen; Web und die GitHub-APK bleiben sonst blind.
  //
  // `worthReporting` siebt vorher aus, was hier regelmäßig landet, ohne dass
  // etwas kaputt ist (abgebrochene Kachel-Aufträge, Abfragen nach dem
  // Abmelden) — dann auch nicht ins Log: Bei 193 Fällen pro Woche wäre es
  // dort genauso Rauschen wie in der Datenbank (Issue #136). Nur diese
  // globalen Handler filtern; ein `logError` mit eigenem Kontext meldet
  // weiterhin alles.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    if (worthReporting(details.exception)) {
      logError('Flutter-Fehler', details.exception, details.stack);
    }
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (worthReporting(error)) logError('Unbehandelter Fehler', error, stack);
    return false; // false: Standardbehandlung nicht unterdrücken.
  };

  // Warum die App beim letzten Mal starb (Issue #147). Bewusst ohne await:
  // Der Start darf darauf nicht warten, und scheitern darf es sowieso.
  unawaited(ExitReporter(
    exits: ExitInfoRepository(),
    reports: reports,
  ).reportPending());

  // Vor runApp, damit die gespeicherte Kartenquelle schon im ersten Frame
  // gilt (Issue #145). Der Aufruf liest eine kleine lokale Datei — er darf
  // den Start aufhalten, ein sichtbares Umschalten der Karte nicht.
  final settings = PrefsSettings(await SharedPreferences.getInstance());
  // Erstlauf-Schutz fürs Buddy-Fund-Banner — Begründung an der Funktion.
  await ensureFindSeenMarker(settings);

  runApp(ProviderScope(
    overrides: [settingsProvider.overrideWithValue(settings)],
    child: const PilzBuddyApp(),
  ));
}
