import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors.dart';

extension SessionUid on SupabaseClient {
  /// Die eigene Nutzer-id — oder [NotSignedInException], wenn niemand
  /// angemeldet ist.
  ///
  /// Ersetzt `auth.currentUser!.id`, das in fünf Repositories stand. Das
  /// `!` warf beim Abmelden und beim Token-Ablauf ein nichtssagendes
  /// „Null check operator used on a null value" — am häufigsten im Poll der
  /// Freundes-Standorte, der ein paar Sekunden weiterläuft, nachdem die
  /// Sitzung weg ist (Issue #124). Ein eigener Typ macht daraus einen Fall,
  /// den der Aufrufer erkennen und behandeln kann.
  ///
  /// Bewusst weiterhin eine Ausnahme und kein `null`: Wer eine Zeile
  /// schreiben will, ohne angemeldet zu sein, hat einen Fehler im Ablauf —
  /// still nichts zu tun würde ihn verstecken.
  String get requireUid {
    final id = auth.currentUser?.id;
    if (id == null) throw const NotSignedInException();
    return id;
  }
}
