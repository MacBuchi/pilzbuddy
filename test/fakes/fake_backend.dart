// In-Memory-Backend für Szenario-Tests: bildet Supabase-Tabellen und die
// RLS-Freigaberegeln aus supabase/schema.sql nach, damit komplette
// App-Abläufe ohne Netz und ohne Emulator in `flutter test` laufen.
//
// Wichtig: Die echten Freigaberegeln erzwingt der Server (RLS). Die Fakes
// spiegeln sie nur, damit die UI-Reaktion darauf testbar ist — sie ersetzen
// keinen RLS-Test (dafür gibt es die REST-Skripte gegen das Live-Projekt).
import 'dart:async';
import 'dart:io';

import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/data/app_config_repository.dart';
import 'package:pilzbuddy/data/auth_repository.dart';
import 'package:pilzbuddy/data/feedback_repository.dart';
import 'package:pilzbuddy/data/friend_repository.dart';
import 'package:pilzbuddy/data/live_share_repository.dart';
import 'package:pilzbuddy/data/profile_repository.dart';
import 'package:pilzbuddy/data/spot_repository.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/friend_location.dart';
import 'package:pilzbuddy/models/friendship.dart';
import 'package:pilzbuddy/models/profile.dart';
import 'package:pilzbuddy/models/spot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeUser {
  FakeUser({
    required this.id,
    required this.email,
    required this.password,
    required this.username,
    this.avatar = 0,
    this.shareSpotsDefault = true,
    this.shareDetails = true,
    this.emailConfirmed = true,
  });

  final String id;
  // Nicht final: der Passwort-Reset bzw. der E-Mail-Wechsel ändern sie
  // wirklich, damit Tests den Effekt prüfen können und nicht nur den
  // Aufruf.
  String email;
  String password;
  // Nicht final: „Benutzername ändern" — gleiche Begründung.
  String username;
  int avatar;
  bool shareSpotsDefault;
  bool shareDetails;
  /// Bestandsnutzer sind alle bestätigt (Autoconfirm), deshalb Vorgabe true.
  bool emailConfirmed;
}

class FakeSpotRow {
  FakeSpotRow({
    required this.id,
    required this.ownerId,
    this.name,
    required this.lat,
    required this.lng,
    this.sharingExcluded = false,
  });

  final String id;
  final String ownerId;
  String? name;
  final double lat;
  final double lng;
  bool sharingExcluded;
  final List<Find> finds = [];
}

class FakeFriendshipRow {
  FakeFriendshipRow({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    this.status = 'pending',
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  String status; // 'pending' | 'accepted'
}

class FakeLiveShareRow {
  FakeLiveShareRow({
    required this.userId,
    required this.lat,
    required this.lng,
    required this.expiresAt,
  });

  final String userId;
  double lat;
  double lng;
  DateTime expiresAt;
}

class FakeBackend {
  final users = <FakeUser>[];
  final spots = <FakeSpotRow>[];
  final friendships = <FakeFriendshipRow>[];
  final liveLocations = <FakeLiveShareRow>[];
  final feedback = <Map<String, dynamic>>[];

  /// Adressen, für die ein Reset-Code angefordert wurde — auch solche ohne
  /// Konto, denn die App darf beide Fälle nicht unterscheiden.
  final passwordResets = <String>[];

  /// Der Code, den der Fake in der „Mail" verschickt. Fest statt zufällig,
  /// damit Tests ihn kennen; echt sind es sechs Ziffern von GoTrue.
  static const resetCode = '123456';

  /// Bewusst ein ANDERER Code als [resetCode]: Echt sind Bestätigung
  /// (`OtpType.signup`) und Reset (`OtpType.recovery`) zwei Paar Schuhe.
  /// Mit einem gemeinsamen Code käme ein Screen, der versehentlich die
  /// falsche Repository-Methode ruft, im Test trotzdem durch.
  static const signupCode = '654321';

  /// Spiegelt „Confirm email" im Supabase-Dashboard. Vorgabe false = wie
  /// heute live; Tests, die den Bestätigungs-Weg prüfen, schalten es an.
  bool requireEmailConfirmation = false;

  /// Adressen, an die eine Bestätigungsmail rausging (auch erneut).
  final confirmationMails = <String>[];

  /// Wie oft dieselbe Adresse eine Bestätigungsmail bekommen darf, bevor
  /// GoTrues Rate Limit greift. Vorgabe hoch genug, dass bestehende Tests
  /// nichts davon merken; der Rate-Limit-Test setzt sie herunter.
  int confirmationMailLimit = 100;

  /// Steht für die „Leaked Password Protection" im Dashboard: Passwörter,
  /// die HaveIBeenPwned kennt, lehnt Supabase mit `weak_password` ab.
  final weakPasswords = <String>{'passwort123'};

  String? currentUserId;
  final _authEvents = StreamController<AuthState>.broadcast();
  var _nextId = 0;

  Stream<AuthState> get authEvents => _authEvents.stream;

  String _newId(String prefix) => '$prefix-${++_nextId}';

  void dispose() => _authEvents.close();

  FakeUser addUser({
    required String username,
    String? email,
    String password = 'geheim123',
    int avatar = 0,
    bool shareSpotsDefault = true,
    bool shareDetails = true,
    bool emailConfirmed = true,
  }) {
    final user = FakeUser(
      id: _newId('user'),
      email: email ?? '$username@test.de',
      password: password,
      username: username,
      avatar: avatar,
      shareSpotsDefault: shareSpotsDefault,
      shareDetails: shareDetails,
      emailConfirmed: emailConfirmed,
    );
    users.add(user);
    return user;
  }

  /// Spot inkl. optionalem erstem Fund — wie `addSpot` in der App.
  String addSpot({
    required String ownerId,
    double lat = 51.1634,
    double lng = 10.4477,
    String? name,
    String? species,
    int? count,
    DateTime? foundOn,
    bool sharingExcluded = false,
  }) {
    final row = FakeSpotRow(
      id: _newId('spot'),
      ownerId: ownerId,
      name: name,
      lat: lat,
      lng: lng,
      sharingExcluded: sharingExcluded,
    );
    spots.add(row);
    if (species != null || foundOn != null) {
      addFindRow(row.id, species: species, count: count, foundOn: foundOn);
    }
    return row.id;
  }

  /// [authorId] wie `finds.author_id` (Patch 014) — ohne Angabe der
  /// Spot-Besitzer, wie es der Backfill für Bestandsdaten macht.
  /// [createdAt] für Tests, die das Buddy-Fund-Banner (#202) gegen einen
  /// festen „gesehen bis"-Marker prüfen.
  /// [blank] wie `finds.blank` (Patch 015): „Nichts gefunden".
  void addFindRow(
    String spotId, {
    String? species,
    int? count,
    DateTime? foundOn,
    String? note,
    String? authorId,
    DateTime? createdAt,
    bool blank = false,
  }) {
    final row = spots.firstWhere((s) => s.id == spotId);
    // Spiegelt den Constraint `finds_blank_leer`: Ein Leergang trägt
    // weder Art noch Anzahl. Ohne diese Prüfung könnte ein Test einen
    // Zustand herstellen, den die Datenbank ablehnt.
    if (blank && (species != null || count != null)) {
      throw ArgumentError(
          'Ein Leergang trägt weder Art noch Anzahl (finds_blank_leer).');
    }
    row.finds.add(Find(
      id: _newId('find'),
      spotId: spotId,
      species: species,
      count: count,
      foundOn: foundOn ?? DateTime.now(),
      note: note,
      createdAt: createdAt ?? DateTime.now(),
      authorId: authorId ?? row.ownerId,
      blank: blank,
    ));
  }

  String addFriendship(
    String requesterId,
    String addresseeId, {
    String status = 'accepted',
  }) {
    final row = FakeFriendshipRow(
      id: _newId('friendship'),
      requesterId: requesterId,
      addresseeId: addresseeId,
      status: status,
    );
    friendships.add(row);
    return row.id;
  }

  /// Live-Standort-Freigabe eines Nutzers (Standard: läuft in 1 h ab).
  void addLiveShare(
    String userId, {
    double lat = 51.1634,
    double lng = 10.4477,
    DateTime? expiresAt,
  }) {
    liveLocations.add(FakeLiveShareRow(
      userId: userId,
      lat: lat,
      lng: lng,
      expiresAt:
          expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
  }

  /// Test-Setup: Nutzer direkt anmelden, ohne den Login-Screen zu bedienen.
  void signInAs(String userId) => currentUserId = userId;

  FakeUser userById(String id) => users.firstWhere((u) => u.id == id);

  /// Wie der unique-Index `profiles_username_lower_key` (Patch 013):
  /// Vergeben ist ein Name auch, wenn er nur anders geschrieben ist.
  bool usernameTaken(String username) => users
      .any((u) => u.username.toLowerCase() == username.toLowerCase());

  /// Wie oft „andere Geräte abmelden" widerrufen hat — einzelne fremde
  /// Sitzungen modelliert der Fake nicht, aber der Effekt muss prüfbar
  /// sein und die eigene Sitzung unangetastet bleiben.
  int otherSessionsRevoked = 0;

  /// Der laufende E-Mail-Wechsel — wie in echt („Secure email change")
  /// mit ZWEI Codes, je einem pro Postfach. Erst wenn beide eingelöst
  /// sind, wird die Adresse wirklich umgestellt.
  String? pendingEmailChange;
  final emailChangeOldCode = '111222';
  final emailChangeNewCode = '333444';
  bool emailChangeOldConfirmed = false;
  bool emailChangeNewConfirmed = false;

  /// Wie die SQL-Funktion `are_friends`: nur akzeptierte Freundschaften.
  bool areFriends(String a, String b) => friendships.any((f) =>
      f.status == 'accepted' &&
      ((f.requesterId == a && f.addresseeId == b) ||
          (f.requesterId == b && f.addresseeId == a)));

  void setCurrentUser(FakeUser? user, AuthChangeEvent event) {
    currentUserId = user?.id;
    _authEvents.add(AuthState(event, user == null ? null : sessionFor(user)));
  }

  Session sessionFor(FakeUser user) => Session(
        accessToken: 'fake-token-${user.id}',
        tokenType: 'bearer',
        user: User(
          id: user.id,
          appMetadata: const {},
          userMetadata: {'username': user.username},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      );
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.backend);

  final FakeBackend backend;

  @override
  Session? get currentSession => backend.currentUserId == null
      ? null
      : backend.sessionFor(backend.userById(backend.currentUserId!));

  @override
  String? get currentUserId => backend.currentUserId;

  @override
  Stream<AuthState> get onAuthStateChange => backend.authEvents;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final user = backend.users
        .where((u) => u.email == email && u.password == password)
        .firstOrNull;
    if (user == null) {
      throw const AuthException('Invalid login credentials', statusCode: '400');
    }
    // Wie GoTrue mit Bestätigungspflicht: eigener Fehlercode, damit die
    // App nicht „E-Mail oder Passwort falsch" behauptet.
    if (!user.emailConfirmed) {
      throw const AuthException('Email not confirmed',
          statusCode: '400', code: 'email_not_confirmed');
    }
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    if (backend.usernameTaken(username)) {
      // Wie in echt: der Profil-Trigger scheitert am unique-Benutzernamen —
      // seit Patch 013 auch über Groß-/Kleinschreibung hinweg.
      throw const AuthException('Database error saving new user',
          statusCode: '500');
    }
    final user = backend.addUser(
        username: username,
        email: email,
        password: password,
        emailConfirmed: !backend.requireEmailConfirmation);
    if (backend.requireEmailConfirmation) {
      // Wie echt: Konto ja, Sitzung nein — erst die Bestätigung öffnet es.
      backend.confirmationMails.add(email);
      return true;
    }
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
    return false;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    final sent = backend.confirmationMails.where((m) => m == email).length;
    if (sent >= backend.confirmationMailLimit) {
      throw const AuthException('For security purposes, you can only request '
          'this after 60 seconds.',
          statusCode: '429', code: 'over_email_send_rate_limit');
    }
    backend.confirmationMails.add(email);
  }

  @override
  Future<void> confirmEmailWithCode({
    required String email,
    required String code,
  }) async {
    final user = backend.users.where((u) => u.email == email).firstOrNull;
    if (user == null || code != FakeBackend.signupCode) {
      throw const AuthException('Token has expired or is invalid',
          statusCode: '403', code: 'otp_expired');
    }
    // Wie echt: verifyOTP bestätigt UND meldet an.
    user.emailConfirmed = true;
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
  }

  @override
  Future<void> signOut() async =>
      backend.setCurrentUser(null, AuthChangeEvent.signedOut);

  @override
  String? get currentEmail {
    final uid = backend.currentUserId;
    return uid == null ? null : backend.userById(uid).email;
  }

  @override
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final uid = backend.currentUserId;
    if (uid == null) {
      throw const AuthException('Keine angemeldete Sitzung.');
    }
    final user = backend.userById(uid);
    // Wie in echt: erst die frische Anmeldung — das falsche Passwort
    // scheitert, BEVOR irgendetwas angestoßen wird.
    if (user.password != currentPassword) {
      throw const AuthException('Invalid login credentials',
          statusCode: '400', code: 'invalid_credentials');
    }
    if (backend.users.any(
        (u) => u.email.toLowerCase() == newEmail.toLowerCase())) {
      throw const AuthException(
          'A user with this email address has already been registered',
          statusCode: '422',
          code: 'email_exists');
    }
    backend.pendingEmailChange = newEmail;
    backend.emailChangeOldConfirmed = false;
    backend.emailChangeNewConfirmed = false;
  }

  @override
  Future<void> confirmEmailChange({
    required String email,
    required String code,
  }) async {
    final uid = backend.currentUserId;
    final pending = backend.pendingEmailChange;
    if (uid == null || pending == null) {
      throw const AuthException('Kein laufender Adresswechsel.');
    }
    final user = backend.userById(uid);
    // Wie gemessen: je Postfach ein eigener Code; erst BEIDE zusammen
    // vollziehen den Wechsel. Ein falscher Code ist otp_expired — wie
    // bei Reset und Registrierung.
    if (email == user.email && code == backend.emailChangeOldCode) {
      backend.emailChangeOldConfirmed = true;
    } else if (email == pending && code == backend.emailChangeNewCode) {
      backend.emailChangeNewConfirmed = true;
    } else {
      throw const AuthException('Token has expired or is invalid',
          statusCode: '403', code: 'otp_expired');
    }
    if (backend.emailChangeOldConfirmed &&
        backend.emailChangeNewConfirmed) {
      user.email = pending;
      backend.pendingEmailChange = null;
      // Wie in echt: der zweite Code bringt eine frische Sitzung mit —
      // das SDK feuert ein Auth-Event, und die Profil-Kachel hört
      // darauf (Read-after-write der neuen Adresse).
      backend.setCurrentUser(user, AuthChangeEvent.userUpdated);
    }
  }

  @override
  Future<void> signOutOtherDevices() async {
    // Andere Sitzungen modelliert der Fake nicht einzeln — der Zähler
    // hält fest, DASS widerrufen wurde, und die eigene Sitzung bleibt
    // unangetastet (kein setCurrentUser, kein Event).
    backend.otherSessionsRevoked++;
  }

  /// Nimmt jede Adresse an — auch unbekannte. Genau so verhält sich
  /// Supabase, damit die Antwort kein Konto-Orakel wird.
  @override
  Future<void> sendPasswordResetCode(String email) async {
    backend.passwordResets.add(email);
  }

  /// Spiegelt die echte Reihenfolge: `verifyOTP` meldet die Sitzung mit
  /// `passwordRecovery` an, erst `updateUser` setzt das Passwort und meldet
  /// `userUpdated`. Der Router hängt an genau diesem Unterschied — hier
  /// beides zu verschmelzen würde den Test am Kernpunkt vorbeiführen.
  @override
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final user = backend.users.where((u) => u.email == email).firstOrNull;
    if (user == null || code != FakeBackend.resetCode) {
      // Wie GoTrue: derselbe Fehler für falschen Code und unbekannte
      // Adresse — sonst wäre auch das ein Konto-Orakel.
      throw const AuthException('Token has expired or is invalid',
          statusCode: '403', code: 'otp_expired');
    }
    backend.setCurrentUser(user, AuthChangeEvent.passwordRecovery);
    if (backend.weakPasswords.contains(newPassword)) {
      throw const AuthException('Password is known to be weak and easy to '
          'guess, please choose a different one.',
          statusCode: '422', code: 'weak_password');
    }
    user.password = newPassword;
    backend.setCurrentUser(user, AuthChangeEvent.userUpdated);
  }

  /// Spiegelt „Secure password change": Ohne das aktuelle Passwort geht
  /// nichts, denn die echte Methode meldet sich damit zuerst neu an. Der
  /// Fake kann diese Härtung nur behaupten — bewiesen wird sie gegen echtes
  /// GoTrue in `tool/auth_reset_check.sh`.
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final uid = backend.currentUserId;
    if (uid == null) {
      throw const AuthException('Keine angemeldete Sitzung.');
    }
    final user = backend.userById(uid);
    if (user.password != currentPassword) {
      throw const AuthException('Invalid login credentials',
          statusCode: '400', code: 'invalid_credentials');
    }
    if (newPassword == currentPassword) {
      throw const AuthException('New password should be different',
          statusCode: '422', code: 'same_password');
    }
    if (backend.weakPasswords.contains(newPassword)) {
      throw const AuthException('Password is known to be weak and easy to '
          'guess, please choose a different one.',
          statusCode: '422', code: 'weak_password');
    }
    user.password = newPassword;
    backend.setCurrentUser(user, AuthChangeEvent.userUpdated);
  }

  /// Bildet die Kaskade aus `supabase/schema.sql` nach: alle Tabellen hängen
  /// per `on delete cascade` an profiles, profiles an auth.users. Echt räumt
  /// deshalb eine einzige Zeile alles ab — hier muss es von Hand passieren,
  /// damit Tests den tatsächlichen Effekt prüfen können und nicht nur, dass
  /// die Methode aufgerufen wurde.
  @override
  Future<void> deleteAccount() async {
    final uid = backend.currentUserId;
    if (uid == null) return;
    // Spiegel der finds_author_id_fkey-Kaskade (Patch 014): Auch Funde,
    // die der Nutzer an FREMDEN Spots eingetragen hat, verschwinden.
    for (final s in backend.spots) {
      s.finds.removeWhere((f) => f.authorId == uid);
    }
    backend.spots.removeWhere((s) => s.ownerId == uid);
    backend.friendships
        .removeWhere((f) => f.requesterId == uid || f.addresseeId == uid);
    backend.liveLocations.removeWhere((l) => l.userId == uid);
    backend.feedback.removeWhere((f) => f['user_id'] == uid);
    backend.users.removeWhere((u) => u.id == uid);
    backend.setCurrentUser(null, AuthChangeEvent.signedOut);
  }
}

class FakeSpotRepository implements SpotRepository {
  FakeSpotRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  Spot _toSpot(FakeSpotRow row,
          {required bool own, FakeUser? owner, required List<Find> finds}) =>
      Spot(
        id: row.id,
        ownerId: row.ownerId,
        name: row.name,
        lat: row.lat,
        lng: row.lng,
        sharingExcluded: row.sharingExcluded,
        isOwn: own,
        ownerUsername: owner?.username,
        ownerAvatar: owner?.avatar ?? 0,
        finds: finds,
      );

  /// Baut einen gespeicherten Fund aus Sicht des Betrachters neu — wie
  /// `Find.fromJson` mit dem author-Embed: `isOwn` und die Zuschreibung
  /// entstehen erst beim Lesen, nicht beim Speichern.
  Find _viewFind(Find f) {
    final author = f.authorId == null ? null : backend.userById(f.authorId!);
    return Find(
      id: f.id,
      spotId: f.spotId,
      species: f.species,
      count: f.count,
      foundOn: f.foundOn,
      note: f.note,
      createdAt: f.createdAt,
      authorId: f.authorId,
      authorUsername: author?.username,
      authorAvatar: author?.avatar ?? 0,
      isOwn: f.authorId == null || f.authorId == _uid,
      blank: f.blank,
    );
  }

  /// Setzt die Herkunft, die `fetchMySpots` meldet: nicht `null` heißt
  /// „aus dem Zwischenspeicher, von diesem Zeitpunkt" — damit sich das
  /// Offline-Banner prüfen lässt, ohne echte Dateien anzufassen.
  DateTime? cachedAt;

  /// Lässt den nächsten Abruf scheitern — für den Fall „kein Empfang und
  /// auch nichts zwischengespeichert".
  bool failNextFetch = false;

  @override
  Future<SpotsSnapshot> fetchMySpots() async {
    if (failNextFetch) {
      failNextFetch = false;
      throw const SocketException('kein Netz (Fake)');
    }
    return (
      spots: [
        for (final row in backend.spots)
          if (row.ownerId == _uid)
            _toSpot(row, own: true, finds: [
              // Spiegel von finds_author_all + finds_owner_select
              // (Patch 014): eigene Funde immer, fremde nur solange die
              // Freigabe-Beziehung zum Autor besteht — dieselbe
              // Freundschaft, der EIGENE globale Schalter, derselbe
              // Spot-Ausschluss.
              for (final f in row.finds)
                if (f.authorId == null ||
                    f.authorId == _uid ||
                    (backend.areFriends(_uid, f.authorId!) &&
                        backend.userById(_uid).shareSpotsDefault &&
                        !row.sharingExcluded))
                  _viewFind(f),
            ]),
      ],
      cachedAt: cachedAt,
    );
  }

  /// Spiegelt die RLS-Policies: sichtbar sind Spots akzeptierter Freunde,
  /// wenn deren globales Teilen an ist und der Spot nicht ausgeschlossen
  /// wurde. Von den Funden kommen die des BESITZERS nur mit dessen
  /// Detail-Freigabe, die EIGENEN immer (finds_author_all) — und die
  /// dritter Buddies nie (Patch 014).
  @override
  Future<List<Spot>> fetchFriendSpots() async => [
        for (final row in backend.spots)
          if (row.ownerId != _uid &&
              backend.areFriends(_uid, row.ownerId) &&
              backend.userById(row.ownerId).shareSpotsDefault &&
              !row.sharingExcluded)
            Spot(
              id: row.id,
              ownerId: row.ownerId,
              name: row.name,
              lat: row.lat,
              lng: row.lng,
              isOwn: false,
              ownerUsername: backend.userById(row.ownerId).username,
              ownerAvatar: backend.userById(row.ownerId).avatar,
              finds: [
                for (final f in row.finds)
                  if (f.authorId == _uid ||
                      ((f.authorId == null || f.authorId == row.ownerId) &&
                          backend.userById(row.ownerId).shareDetails))
                    _viewFind(f),
              ],
            ),
      ];

  @override
  Future<void> addSpot({
    required double lat,
    required double lng,
    String? name,
    required List<NewFind> finds,
  }) async {
    final id = backend.addSpot(ownerId: _uid, lat: lat, lng: lng, name: name);
    // Wie im echten Repository über addFinds, damit die Normalisierung des
    // Artnamens nur an einer Stelle steht.
    await addFinds(spotId: id, finds: finds);
  }

  /// Spiegelt `SpotRepository.restoreSpot` (#112): ein Spot mit beliebig
  /// vielen Funden, mit Freigabe-Flag, auch ganz ohne Fund.
  ///
  /// Normalisiert die Artnamen genau wie das echte Repository — das ist
  /// der Grund, warum dieser Weg hier überhaupt nachgebaut wird und nicht
  /// einfach `backend.addSpot` mehrfach aufruft.
  ///
  /// **Grenze, gemessen mit einer Gegenprobe:** Was hier steht, ersetzt
  /// das echte Repository — läuft ein Test grün, ist damit die *Absicht*
  /// belegt, nicht die Zuordnung der Felder im echten Insert. Wer dort
  /// `sharing_excluded` auf einen festen Wert setzt, bleibt für jeden
  /// Flow-Test unsichtbar. Gegen die Fehlerklasse, die sich prüfen lässt
  /// (falscher Spaltenname), steht `tool/schema_check.sh` mit den
  /// Schreibspalten von `spots` und `finds`.
  @override
  Future<void> restoreSpot({
    required double lat,
    required double lng,
    String? name,
    bool sharingExcluded = false,
    required List<NewFind> finds,
  }) async {
    final id = backend.addSpot(
        ownerId: _uid,
        lat: lat,
        lng: lng,
        name: name,
        sharingExcluded: sharingExcluded);
    await addFinds(spotId: id, finds: finds);
  }

  /// Spiegelt `SpotRepository.addFinds`: gespeichert wird die
  /// Hauptbezeichnung der Art. Ohne das verhielte sich der Harness anders
  /// als die App — ein Fund, den die App als „Herbsttrompete" ablegt, läge
  /// hier als „Totentrompete", und kein Test würde den Unterschied sehen.
  /// `FakeBackend.addSpot` normalisiert bewusst NICHT: damit legen Tests
  /// Bestandsdaten aus der Zeit vor der Vereinheitlichung an.
  @override
  Future<void> addFinds({
    required String spotId,
    required List<NewFind> finds,
  }) async {
    if (finds.isEmpty) return;
    // Spiegel des with check von finds_author_all (Patch 014): Schreiben
    // darf, wer den Spot besitzt ODER ihn über die volle Freigabe-
    // Beziehung sieht. Alles andere beantwortet die echte RLS mit 42501.
    final row = backend.spots.firstWhere((s) => s.id == spotId);
    final allowed = row.ownerId == _uid ||
        (backend.areFriends(row.ownerId, _uid) &&
            !row.sharingExcluded &&
            backend.userById(row.ownerId).shareSpotsDefault);
    if (!allowed) {
      throw const PostgrestException(
          message:
              'new row violates row-level security policy for table "finds"',
          code: '42501');
    }
    for (final find in finds) {
      backend.addFindRow(spotId,
          species: canonicalSpecies(find.species),
          count: find.count,
          foundOn: find.foundOn,
          note: find.note,
          authorId: _uid,
          blank: find.blank);
    }
  }

  /// Spiegelt `SpotRepository.updateFind` (#240) samt der Grenze, die
  /// live `finds_author_all` zieht: geändert werden darf nur der EIGENE
  /// Fund (`using`), und nur solange der Spot sichtbar ist (`with check`
  /// — derselbe Ausdruck wie beim Anlegen).
  ///
  /// Ein abgelehnter Fall wirft hier [WriteRejectedException] und keinen
  /// Postgrest-Fehler: Live trifft die Anfrage einfach keine Zeile, und
  /// genau dieses stille Nichts fängt das echte Repository mit `.select()`
  /// ab. Ein PostgrestException an dieser Stelle wäre bequemer und würde
  /// eine Sicherung vortäuschen, die es nicht gibt.
  @override
  Future<void> updateFind({
    required String findId,
    required NewFind find,
  }) async {
    for (final row in backend.spots) {
      final index = row.finds.indexWhere((f) => f.id == findId);
      if (index < 0) continue;
      final old = row.finds[index];
      final visible = row.ownerId == _uid ||
          (backend.areFriends(row.ownerId, _uid) &&
              !row.sharingExcluded &&
              backend.userById(row.ownerId).shareSpotsDefault);
      if (old.authorId != _uid || !visible) break;
      row.finds[index] = Find(
        id: old.id,
        spotId: old.spotId,
        // Normalisiert wie das echte Repository — sonst käme über den
        // Korrekturweg eine Schreibweise in den Bestand, die der
        // Anlegeweg nie erzeugt.
        species: canonicalSpecies(find.species),
        count: find.count,
        foundOn: find.foundOn,
        note: find.note,
        createdAt: old.createdAt,
        authorId: old.authorId,
        blank: find.blank,
      );
      return;
    }
    throw const WriteRejectedException('Fund ändern');
  }

  /// Spiegelt `SpotRepository.deleteFind` (#240). Anders als beim Ändern
  /// zählt hier NUR der Autor: Das `using` von `finds_author_all` fragt
  /// nicht nach dem Spot, wer seine Daten zurückziehen will, kann das
  /// also auch nach dem Ende einer Freigabe.
  @override
  Future<void> deleteFind(String findId) async {
    for (final row in backend.spots) {
      final index = row.finds.indexWhere((f) => f.id == findId);
      if (index < 0) continue;
      if (row.finds[index].authorId != _uid) break;
      row.finds.removeAt(index);
      return;
    }
    throw const WriteRejectedException('Fund löschen');
  }

  /// Löschen nimmt die Funde mit — `finds.spot_id … on delete cascade`.
  ///
  /// Die Funde werden ausdrücklich geleert und nicht bloß mit der Zeile
  /// aus der Liste genommen: Wer noch eine Referenz auf die Zeile hält,
  /// bekäme sonst eine Fundliste zu sehen, die es live nicht mehr gibt —
  /// und genau daran hing beim Zusammenführen (#215) die Frage, ob die
  /// Reihenfolge „erst umhängen, dann löschen" wirklich nötig ist. Ohne
  /// diese Zeile bliebe sie ungeprüft.
  @override
  Future<void> deleteSpot(String spotId) async {
    for (final row in backend.spots) {
      if (row.id == spotId && row.ownerId == _uid) row.finds.clear();
    }
    backend.spots.removeWhere((s) => s.id == spotId && s.ownerId == _uid);
  }

  /// Spiegelt `SpotRepository.mergeSpots` (#215) — inklusive der Grenze,
  /// die live die RLS zieht: `finds_author_all` erlaubt das Umhängen nur
  /// für `author_id = auth.uid()`, ein FREMDER Fund bleibt also liegen und
  /// fällt danach der Lösch-Kaskade zum Opfer. Ohne diesen Nachbau bewiese
  /// ein grüner Test eine Vollständigkeit, die es live nicht gibt.
  ///
  /// Die Oberfläche bietet solche Paare nicht an (`canMerge`); dieser
  /// Nachbau ist der Beleg, dass sie es auch besser nicht täte.
  @override
  Future<void> mergeSpots(
      {required String intoId, required String fromId}) async {
    final from = backend.spots.firstWhere((s) => s.id == fromId);
    final into = backend.spots.firstWhere((s) => s.id == intoId);
    final mine = from.finds.where((f) => f.authorId == _uid).toList();
    for (final find in mine) {
      from.finds.remove(find);
      into.finds.add(find);
    }
    await deleteSpot(fromId);
  }

  @override
  Future<void> setSharingExcluded(String spotId, bool excluded) async =>
      backend.spots.firstWhere((s) => s.id == spotId).sharingExcluded =
          excluded;
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(this.backend);

  final FakeBackend backend;

  FakeUser get _me => backend.userById(backend.currentUserId!);

  @override
  Future<Profile> fetchMyProfile() async => Profile(
        id: _me.id,
        username: _me.username,
        shareSpotsDefault: _me.shareSpotsDefault,
        shareDetails: _me.shareDetails,
        avatar: _me.avatar,
      );

  @override
  Future<void> updateAvatar(int avatar) async => _me.avatar = avatar;

  @override
  Future<void> updateUsername(String username) async {
    // Wie in echt: die unique-Verletzung kommt als PostgREST-Fehler mit
    // SQLSTATE 23505, nicht als Auth-Fehler — und sie greift über
    // Groß-/Kleinschreibung hinweg (Patch 013). Der eigene alte Name
    // zählt nicht als Kollision.
    if (backend.users.any((u) =>
        u.id != _me.id &&
        u.username.toLowerCase() == username.toLowerCase())) {
      throw const PostgrestException(
          message: 'duplicate key value violates unique constraint '
              '"profiles_username_lower_key"',
          code: '23505');
    }
    _me.username = username;
  }

  @override
  Future<void> updateSharing({
    bool? shareSpotsDefault,
    bool? shareDetails,
  }) async {
    if (shareSpotsDefault != null) _me.shareSpotsDefault = shareSpotsDefault;
    if (shareDetails != null) _me.shareDetails = shareDetails;
  }
}

class FakeFriendRepository implements FriendRepository {
  FakeFriendRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  @override
  Future<List<ProfileSearchResult>> search(String query) async {
    final q = query.trim().toLowerCase();
    return [
      for (final u in backend.users)
        if (u.id != _uid &&
            (u.username.toLowerCase().contains(q) ||
                u.email.toLowerCase() == q))
          ProfileSearchResult(id: u.id, username: u.username, avatar: u.avatar),
    ];
  }

  @override
  Future<List<FriendshipEntry>> fetchFriendships() async => [
        for (final f in backend.friendships)
          if (f.requesterId == _uid || f.addresseeId == _uid)
            FriendshipEntry(
              id: f.id,
              status: f.status,
              requesterId: f.requesterId,
              addresseeId: f.addresseeId,
              requesterUsername: backend.userById(f.requesterId).username,
              addresseeUsername: backend.userById(f.addresseeId).username,
              requesterAvatar: backend.userById(f.requesterId).avatar,
              addresseeAvatar: backend.userById(f.addresseeId).avatar,
            ),
      ];

  @override
  Future<void> sendRequest(String addresseeId) async {
    if (backend.friendships.any((f) =>
        (f.requesterId == _uid && f.addresseeId == addresseeId) ||
        (f.requesterId == addresseeId && f.addresseeId == _uid))) {
      // Wie in echt: unique-Constraint auf dem Freundschafts-Paar.
      throw StateError('duplicate friendship');
    }
    backend.addFriendship(_uid, addresseeId, status: 'pending');
  }

  @override
  Future<void> accept(String friendshipId) async =>
      backend.friendships.firstWhere((f) => f.id == friendshipId).status =
          'accepted';

  @override
  Future<void> remove(String friendshipId) async =>
      backend.friendships.removeWhere((f) => f.id == friendshipId);
}

class FakeLiveShareRepository implements LiveShareRepository {
  FakeLiveShareRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  @override
  Future<void> upsertMyLocation({
    required double lat,
    required double lng,
    required DateTime expiresAt,
  }) async {
    final existing =
        backend.liveLocations.where((r) => r.userId == _uid).firstOrNull;
    if (existing == null) {
      backend.liveLocations.add(FakeLiveShareRow(
          userId: _uid, lat: lat, lng: lng, expiresAt: expiresAt));
    } else {
      existing
        ..lat = lat
        ..lng = lng
        ..expiresAt = expiresAt;
    }
  }

  @override
  Future<DateTime?> fetchMyShare() async {
    final row =
        backend.liveLocations.where((r) => r.userId == _uid).firstOrNull;
    if (row == null) return null;
    return row.expiresAt.isAfter(DateTime.now().toUtc()) ? row.expiresAt : null;
  }

  @override
  Future<void> stopSharing() async =>
      backend.liveLocations.removeWhere((r) => r.userId == _uid);

  /// Spiegelt die RLS-Policy: sichtbar sind nicht abgelaufene Freigaben
  /// akzeptierter Freunde (die eigene ausgeblendet).
  @override
  Future<List<FriendLocation>> fetchFriendLocations() async => [
        for (final row in backend.liveLocations)
          if (row.userId != _uid &&
              backend.areFriends(_uid, row.userId) &&
              row.expiresAt.isAfter(DateTime.now().toUtc()))
            FriendLocation(
              userId: row.userId,
              lat: row.lat,
              lng: row.lng,
              expiresAt: row.expiresAt,
              username: backend.userById(row.userId).username,
              avatar: backend.userById(row.userId).avatar,
            ),
      ];
}

class FakeFeedbackRepository implements FeedbackRepository {
  FakeFeedbackRepository(this.backend);

  final FakeBackend backend;

  @override
  Future<void> submit(FeedbackType type, String message) async {
    backend.feedback.add({
      'user_id': backend.currentUserId,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
    });
  }

  @override
  Future<void> submitSpecies(String speciesName, {String? note}) async {
    backend.feedback.add({
      'user_id': backend.currentUserId,
      'type': 'species',
      'species_name': speciesName.trim(),
      'message': note,
    });
  }
}

/// Server-seitige Mindestversion (`app_config`, Patch 012).
///
/// Ohne Angabe liefert die Fake keine Mindestversion — so verhält sich der
/// Harness wie eine Datenbank, die nichts sperrt, und die übrigen Tests
/// merken von der Sperre nichts.
class FakeAppConfigRepository implements AppConfigRepository {
  FakeAppConfigRepository({this.minimumSupportedVersion, this.fails = false});

  final String? minimumSupportedVersion;

  /// Abruf scheitern lassen — der Fall, in dem die App trotzdem starten muss.
  final bool fails;

  @override
  Future<String?> fetchMinimumSupportedVersion() async {
    if (fails) throw Exception('kein Netz');
    return minimumSupportedVersion;
  }
}
