// Neu laden nach einem erfolgreichen Schreibvorgang — und der Unterschied
// zwischen „das Schreiben ist gescheitert" und „das Neuladen ist
// gescheitert".
//
// Das Haus-Muster für Mutationen ist Read-after-write (CLAUDE.md):
// Repo-Aufruf, dann `ref.invalidateSelf(); await future;`. Bis 1.111.1
// stand das `await future` nackt da, und damit fiel ein Fehler des
// ABRUFS in denselben `catch` wie ein Fehler des SCHREIBENS.
//
// Was der Nutzer davon sah (#371, aus dem Wochendigest #341): Der Spot
// lag auf dem Server, aber es gab kein „Spot gespeichert 🍄", sondern
// „Internet verfügbar?" — und die Karte zeigte ihn nicht, weil
// `mySpotListProvider` bei einem Fehler den Vorwert behält. Jedes
// Signal sagte „nicht gespeichert". Der nächste Schritt ist dann, ihn
// noch einmal einzutragen, und weil das eine frische `client_id` ist,
// entsteht ein echter Doppel-Spot. Der Schutz aus Patch 016 greift
// dort nicht: Er sichert den Wiederholversuch DESSELBEN Auftrags, nicht
// die Handeingabe.
//
// **Kein erneuter Versuch an dieser Stelle.** postgrest wiederholt GETs
// von sich aus dreimal (Backoff 1+2+4 s, siehe `fetchTimeout` in
// `spot_repository.dart`) — ein 504 hat vier Versuche hinter sich, und
// ein fünfter wäre nur Wartezeit vor derselben Antwort.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'errors.dart';

/// Was der Oberfläche zu sagen bleibt, wenn geschrieben, aber nicht mehr
/// neu geladen werden konnte.
///
/// Ein eigener Baustein, weil die Aussage an jeder Schreibstelle
/// dieselbe sein muss: **Es ist gespeichert** — wer hier „Fehler" liest,
/// trägt es ein zweites Mal ein (#371). Der Nachsatz erklärt, warum
/// trotzdem nichts zu sehen ist; ohne ihn sähe „gespeichert" bei
/// unveränderter Liste nach einer Lüge aus.
const staleAfterWriteHint = ' — sichtbar, sobald die Liste wieder lädt.';

/// Read-after-write für [AsyncNotifier]-Mutationen.
mixin ReadAfterWrite<T> on AsyncNotifier<T> {
  /// Lädt neu, nachdem geschrieben wurde — und wirft dabei **nicht**.
  ///
  /// Gibt `true` zurück, wenn die Anzeige jetzt frisch ist, und `false`,
  /// wenn der Schreibvorgang durch ist, das Neuladen aber scheiterte.
  ///
  /// Der Fehler verschwindet nicht, er wird nur richtig benannt: Er
  /// läuft mit [what] nach `error_reports`, statt sich als
  /// „Spot speichern" auszugeben. Der Digest verliert damit nichts —
  /// er hört auf, an der falschen Stelle zu suchen.
  ///
  /// Der Zustand des Providers bleibt unangetastet: Nach einem
  /// fehlgeschlagenen Abruf steht er auf `AsyncError` (mit dem Vorwert
  /// darunter). Eine Aufrufstelle, die den Nutzer über die veraltete
  /// Anzeige unterrichten will, fragt danach — der Rückgabewert hier
  /// sagt dasselbe, nur ohne zweiten Zugriff.
  Future<bool> reloadAfterWrite(String what) async {
    ref.invalidateSelf();
    try {
      await future;
      return true;
    } catch (error, stackTrace) {
      logError(what, error, stackTrace);
      return false;
    }
  }
}
