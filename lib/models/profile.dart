// Hinweis: `profiles.display_name` existiert weiter in der Datenbank und
// wird in der Freundesuche angezeigt (ProfileSearchResult) — im eigenen
// Profil wird es nirgends genutzt und ist deshalb hier bewusst weggelassen.

/// Mindestlänge des Benutzernamens — EINE Quelle für Registrierung und
/// „Benutzername ändern" (Muster `minPasswordLength`).
const minUsernameLength = 3;

/// Was am Benutzernamen nicht stimmt — `null`, wenn er in Ordnung ist.
///
/// EINE Prüfung für beide Eingabestellen (Registrierung und
/// „Benutzername ändern"), aus demselben Grund wie [minUsernameLength]:
/// Zwei Kopien wären zwei Antworten auf dieselbe Frage, und die zweite
/// bräche still.
///
/// **Warum die Mailadresse auffallen muss** (#352): Der Benutzername ist
/// öffentlich. Er steht in Freundeslisten, in der Finder-Zeile am Spot
/// und in den Treffern von `search_profiles`. Wer bei der Registrierung
/// aus Versehen seine Adresse einträgt — und das passiert, weil das
/// Mail-Feld direkt daneben liegt —, veröffentlicht sie damit. Die
/// Freundessuche baut gerade darauf, dass das NICHT passiert: Sie findet
/// über die exakte Adresse, und das ist nur so lange kein Verzeichnis,
/// wie die Adressen nicht ohnehin dastehen.
///
/// **Bewusst grob geprüft.** Erkannt wird „etwas @ etwas . etwas" ohne
/// Leerzeichen, mehr nicht. Ein strenger Mail-Prüfausdruck wäre hier der
/// falsche Ehrgeiz: Die Prüfung soll keine Adressen validieren, sondern
/// einen Vertipper abfangen — und alles, was wie eine Adresse AUSSIEHT,
/// ist als öffentlicher Anzeigename ohnehin eine schlechte Wahl. Der
/// Fehler in die andere Richtung (ein @ im Namen, das keine Adresse ist)
/// kostet einen anderen Namen, nicht ein preisgegebenes Postfach.
String? usernameProblem(String username) {
  final name = username.trim();
  if (name.length < minUsernameLength) {
    return 'Der Benutzername braucht mindestens $minUsernameLength Zeichen.';
  }
  if (_emailShaped.hasMatch(name)) {
    return 'Das sieht nach einer E-Mail-Adresse aus. Dein Benutzername ist '
        'für alle sichtbar — nimm lieber einen Namen.';
  }
  return null;
}

final _emailShaped = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class Profile {
  final String id;
  final String username;
  final bool shareSpotsDefault;
  final bool shareDetails;
  final int avatar;

  const Profile({
    required this.id,
    required this.username,
    required this.shareSpotsDefault,
    required this.shareDetails,
    this.avatar = 0,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String,
        shareSpotsDefault: json['share_spots_default'] as bool? ?? true,
        shareDetails: json['share_details'] as bool? ?? true,
        avatar: json['avatar'] as int? ?? 0,
      );
}
