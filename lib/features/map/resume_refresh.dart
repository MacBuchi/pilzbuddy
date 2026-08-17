// Was beim Zurückkehren in die App neu geladen wird — und was nicht
// (#316, zweite Hälfte).
//
// Bis 1.95.0 lud jeder Resume das volle Programm: vier
// Supabase-Abfragen (zwei davon mit kompletten `finds(*)`-Embeds) und
// ZWEI GitHub-Aufrufe (Update-Check, Karten-Katalog) — auch nach einem
// Blick auf die Uhr und zurück. Jetzt entscheidet eine reine Funktion,
// und die Schwellen sind Provider, damit Tests das VERHALTEN fahren
// können statt Konstanten zu behaupten (dieselbe Naht wie bei den
// Poll-Intervallen der Freundes-Standorte).
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// So lange muss die App WEG gewesen sein, bevor überhaupt neu geladen
/// wird. Darunter ist es ein Blick auf die Uhr, kein „Zurückkehren" —
/// in der Zeit ist auf dem Server nichts passiert, was die 30 Sekunden
/// Wartezeit wert wäre.
final resumeRefreshMinAwayProvider =
    Provider<Duration>((ref) => const Duration(seconds: 30));

/// Höchstens so oft gehen die METADATEN-Ziele raus (Update-Check und
/// Karten-Katalog, beide GitHub): Keins davon braucht
/// Sekundenfrische — ein Release und ein Kartenjahrgang ändern sich
/// tage- bis monatsweise.
final resumeMetaRefreshEveryProvider =
    Provider<Duration>((ref) => const Duration(hours: 1));

/// Was ein Resume auslöst.
enum ResumeRefresh {
  /// Kurz weg gewesen — gar nichts neu laden.
  none,

  /// Spots, Freundschaften, installierte Karten — die Dinge, die sich
  /// wirklich geändert haben können, während man weg war.
  local,

  /// Zusätzlich die GitHub-Ziele (Update-Check, Karten-Katalog).
  localAndMeta,
}

/// Die Entscheidung als reine Funktion — testbar ohne Uhr und Widget.
ResumeRefresh decideResumeRefresh({
  required Duration awayFor,
  required Duration sinceMetaRefresh,
  required Duration minAway,
  required Duration metaEvery,
}) {
  if (awayFor < minAway) return ResumeRefresh.none;
  return sinceMetaRefresh >= metaEvery
      ? ResumeRefresh.localAndMeta
      : ResumeRefresh.local;
}
