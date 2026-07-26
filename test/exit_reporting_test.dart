// Der Weg von Androids Beendigungs-Historie in `error_reports` (Issue #147).
//
// Ohne diesen Weg hinterlässt ein ANR oder Absturz gar nichts: `logError`
// sieht nur, was die App überlebt. Genau deshalb blieb #142 unsichtbar, bis
// jemand ein USB-Kabel angesteckt hat.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/data/error_report_repository.dart';
import 'package:pilzbuddy/data/exit_info_repository.dart';
import 'package:pilzbuddy/data/exit_reporting.dart';

/// Ein geschriebener Bericht — geprüft wird der Inhalt, nicht der Aufruf.
class ReportedExit {
  ReportedExit(this.reason, this.summary, this.when, this.trace);

  final String reason;
  final String summary;
  final DateTime when;
  final String? trace;
}

/// Sammelt statt zu schreiben; ohne Netz, wie der Rest der Suite.
class FakeErrorReports implements ErrorReportRepository {
  final exits = <ReportedExit>[];

  @override
  Future<void> reportExit({
    required String reason,
    required String summary,
    required DateTime when,
    String? trace,
  }) async =>
      exits.add(ReportedExit(reason, summary, when, trace));

  @override
  Future<void> report(String context, Object error,
      [StackTrace? stackTrace]) async {}
}

/// Liefert vorgegebene Einträge, statt die Plattform zu fragen.
class _FakeExits implements ExitInfoRepository {
  _FakeExits(this.exits, {this.trace, this.throwOnRead = false});

  final List<AppExit> exits;
  final String? trace;
  final bool throwOnRead;
  int traceCalls = 0;

  @override
  Future<List<AppExit>> recentExits({int limit = 10}) async {
    if (throwOnRead) throw StateError('Kanal fehlt');
    return exits;
  }

  @override
  Future<String?> traceFor(AppExit exit) async {
    traceCalls++;
    return exit.hasTrace ? trace : null;
  }
}

AppExit _exit(String reason, DateTime when,
        {int rssKb = 0, bool hasTrace = false}) =>
    AppExit(
      timestamp: when,
      reason: reason,
      description: 'beschreibung',
      rssKb: rssKb,
      hasTrace: hasTrace,
    );

void main() {
  late Directory tempDir;
  ExitReporter reporter(FakeErrorReports reports, _FakeExits exits) =>
      ExitReporter(
        exits: exits,
        reports: reports,
        directory: () async => tempDir,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pilzbuddy_exit_test');
  });
  tearDown(() async {
    setErrorSink(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('Ein ANR wird gemeldet, mit Zeitpunkt und Thread-Dump', () async {
    final when = DateTime(2026, 7, 26, 15, 39);
    final reports = FakeErrorReports();
    final exits = _FakeExits(
      [_exit('ANR', when, rssKb: 1900 * 1024, hasTrace: true)],
      trace: '"main" prio=5 tid=1 Native',
    );

    await reporter(reports, exits).reportPending();

    expect(reports.exits, hasLength(1));
    final report = reports.exits.single;
    expect(report.reason, 'ANR');
    expect(report.when, when,
        reason: 'Der Todeszeitpunkt, nicht der Meldezeitpunkt — sonst landet '
            'ein Absturz von Freitagnacht im Digest der Folgewoche.');
    expect(report.trace, contains('"main"'));
    expect(report.summary, contains('RSS 1900 MB'),
        reason: 'Bei #142 zeigte der RSS die Ursache vor jedem Stacktrace.');
  });

  test('Ein normales Beenden wird NICHT gemeldet', () async {
    // Sonst füllt jedes Wegwischen aus der Übersicht den Wochendigest —
    // dieselbe Lehre wie #124 und #136.
    final reports = FakeErrorReports();
    final exits = _FakeExits([
      _exit('USER_REQUESTED', DateTime(2026, 7, 26, 12)),
      _exit('EXIT_SELF', DateTime(2026, 7, 26, 13)),
      _exit('OTHER', DateTime(2026, 7, 26, 14)),
    ]);

    await reporter(reports, exits).reportPending();

    expect(reports.exits, isEmpty);
  });

  test('Derselbe Eintrag wird beim zweiten Start nicht erneut gemeldet',
      () async {
    final reports = FakeErrorReports();
    final exits = _FakeExits([_exit('CRASH', DateTime(2026, 7, 26, 15))]);

    await reporter(reports, exits).reportPending();
    await reporter(reports, exits).reportPending();

    expect(reports.exits, hasLength(1));
  });

  test('Nur Einträge nach dem letzten gemeldeten kommen dazu', () async {
    final reports = FakeErrorReports();
    final alt = _exit('ANR', DateTime(2026, 7, 26, 10));
    final neu = _exit('ANR', DateTime(2026, 7, 26, 20));

    await reporter(reports, _FakeExits([alt])).reportPending();
    await reporter(reports, _FakeExits([alt, neu])).reportPending();

    expect(reports.exits.map((e) => e.when), [alt.timestamp, neu.timestamp]);
  });

  test('Auch ohne meldbare Einträge rückt der Merker vor', () async {
    // Sonst wird die Historie bei jedem Start erneut durchgesehen.
    final reports = FakeErrorReports();
    final harmlos = _exit('USER_REQUESTED', DateTime(2026, 7, 26, 18));
    await reporter(reports, _FakeExits([harmlos])).reportPending();

    // Ein ANR VOR dem harmlosen Eintrag gilt damit als erledigt.
    final alt = _exit('ANR', DateTime(2026, 7, 26, 9));
    await reporter(reports, _FakeExits([harmlos, alt])).reportPending();

    expect(reports.exits, isEmpty);
  });

  test('Ein kaputter Kanal bricht den Start nicht ab', () async {
    // Diagnose, die den Start gefährdet, ist schlimmer als keine.
    final gemeldet = <String>[];
    setErrorSink((context, _, _) => gemeldet.add(context));
    final reports = FakeErrorReports();

    await expectLater(
      reporter(reports, _FakeExits(const [], throwOnRead: true)).reportPending(),
      completes,
    );
    expect(reports.exits, isEmpty);
    expect(gemeldet, ['Beendigungsgrund melden']);
  });

  test('Ohne ANR wird kein Thread-Dump angefordert', () async {
    // Das Lesen des Dumps ist teuer (Rohdatei ~1,8 MB).
    final reports = FakeErrorReports();
    final exits = _FakeExits([_exit('LOW_MEMORY', DateTime(2026, 7, 26, 15))]);

    await reporter(reports, exits).reportPending();

    expect(reports.exits.single.trace, isNull);
  });
}
