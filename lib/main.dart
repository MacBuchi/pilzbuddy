import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/errors.dart';
import 'core/map_data_license.dart';
import 'core/supabase_config.dart';
import 'data/error_report_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    logError('Flutter-Fehler', details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    logError('Unbehandelter Fehler', error, stack);
    return false; // false: Standardbehandlung nicht unterdrücken.
  };

  runApp(const ProviderScope(child: PilzBuddyApp()));
}
