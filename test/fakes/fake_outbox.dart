// Der Ausgangskorb (#267) im Speicher statt auf Platte.
//
// Nötig aus demselben Grund wie [FakeSpotCache]: `FileOutbox` fragt
// `path_provider` nach dem App-Verzeichnis, und diesen Kanal gibt es im
// Widget-Test nicht — der Abruf der eigenen Spots wartet dann ewig, weil
// er den Korb mitliest.
//
// Was auf der Platte passiert (atomares Schreiben, fremdes Konto,
// unlesbare Datei), beweist `test/outbox_test.dart` gegen ein
// Temp-Verzeichnis.
import 'package:pilzbuddy/data/outbox.dart';

class FakeOutbox implements Outbox {
  FakeOutbox({List<OutboxJob>? jobs, this.uid, this.failOnAppend = false})
      : _jobs = [...?jobs];

  List<OutboxJob> _jobs;

  /// Zu welchem Konto der Inhalt gehört. `null` heißt „passt zu jedem" —
  /// die meisten Tests interessiert die Kontotrennung nicht.
  final String? uid;

  /// Simuliert eine volle oder schreibgeschützte Platte: Dann ist der
  /// Fund nirgends gespeichert, und der Aufrufer muss das melden.
  bool failOnAppend;

  List<OutboxJob> get jobs => List.unmodifiable(_jobs);

  @override
  Future<List<OutboxJob>> read({required String uid}) async =>
      this.uid == null || this.uid == uid ? List.of(_jobs) : const [];

  @override
  Future<void> append(OutboxJob job, {required String uid}) async {
    if (failOnAppend) throw const OutboxUnavailable();
    _jobs = [..._jobs, job];
  }

  @override
  Future<void> replaceAll(List<OutboxJob> jobs, {required String uid}) async {
    _jobs = [...jobs];
  }

  @override
  Future<void> clear() async => _jobs = [];
}
