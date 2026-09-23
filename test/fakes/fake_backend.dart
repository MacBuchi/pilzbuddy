// In-Memory-Backend für Szenario-Tests: bildet Supabase-Tabellen und die
// RLS-Freigaberegeln aus supabase/schema.sql nach, damit komplette
// App-Abläufe ohne Netz und ohne Emulator in `flutter test` laufen.
//
// Wichtig: Die echten Freigaberegeln erzwingt der Server (RLS). Die Fakes
// spiegeln sie nur, damit die UI-Reaktion darauf testbar ist — sie ersetzen
// keinen RLS-Test (dafür gibt es die REST-Skripte gegen das Live-Projekt).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pilzbuddy/core/errors.dart';
import 'package:pilzbuddy/data/species_photo_repository.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/data/app_config_repository.dart';
import 'package:pilzbuddy/data/auth_repository.dart';
import 'package:pilzbuddy/data/feedback_repository.dart';
import 'package:pilzbuddy/data/friend_repository.dart';
import 'package:pilzbuddy/data/push_repository.dart';
import 'package:pilzbuddy/data/live_share_repository.dart';
import 'package:pilzbuddy/data/profile_repository.dart';
import 'package:pilzbuddy/data/spot_repository.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/data/tour_track_repository.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';
import 'package:pilzbuddy/models/buddy_track.dart';
import 'package:pilzbuddy/models/find_position.dart';
import 'package:pilzbuddy/models/friend_location.dart';
import 'package:pilzbuddy/models/friendship.dart';
import 'package:pilzbuddy/core/photo_pipeline.dart';
import 'package:pilzbuddy/data/find_photo_repository.dart';
import 'package:pilzbuddy/data/find_report_repository.dart';
import 'package:pilzbuddy/core/photo_providers.dart';
import 'package:pilzbuddy/models/find_photo.dart';
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
    this.clientId,
  });

  final String id;
  final String ownerId;
  String? name;
  // Veränderlich wie in der Tabelle: `spots_owner_all` ist `for all`,
  // Name und Stelle sind seit #466 korrigierbar. Als `final` hätte der
  // Fake eine Unveränderlichkeit behauptet, die es live nie gab.
  double lat;
  double lng;
  bool sharingExcluded;

  /// Vom Gerät vergebene Kennung (Patch 016) — hier, damit der Fake die
  /// Idempotenz der Wiedervorlage spiegelt und nicht nur behauptet.
  final String? clientId;

  /// Spiegel von `spots.offset_confirmed_at` (Patch 024, #475).
  DateTime? offsetConfirmedAt;

  /// Spiegel von `spots.expected_species` (Patch 025, #499).
  List<String> expectedSpecies = [];

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

class FakeTourTrackRow {
  FakeTourTrackRow({
    required this.userId,
    required this.startedAt,
    required this.points,
    required this.expiresAt,
  });

  final String userId;
  DateTime startedAt;
  List<TourPoint> points;
  DateTime expiresAt;
}

/// Spiegel von `find_photos` (Patch 026, #532).
class FakeFindPhotoRow {
  FakeFindPhotoRow({
    required this.id,
    required this.findId,
    required this.userId,
    required this.key,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String findId;
  final String userId;
  final String key;
  final DateTime createdAt;
  DateTime expiresAt;
}

class FakeBackend {
  final users = <FakeUser>[];
  final spots = <FakeSpotRow>[];

  /// Die Zeilen der Fundfotos — und der Bucket dazu: Pfad → Bytes.
  /// Getrennt wie live, damit ein Test „Objekt ohne Zeile" oder „Zeile
  /// ohne Objekt" nachstellen kann.
  final findPhotos = <FakeFindPhotoRow>[];

  /// Kudos (Patch 028): je (Foto, Nutzer) höchstens einer — der
  /// Primärschlüssel. Gelöscht per Cascade mit dem Foto.
  final findPhotoKudos = <({String photoId, String userId})>[];

  /// Meldungen an iNaturalist (Patch 029): Fund-id → Zeile. Je Fund und
  /// Plattform eine — der Primärschlüssel.
  final findReports = <String, FakeFindReportRow>{};
  final photoObjects = <String, Uint8List>{};

  /// Der Bucket `feedback-photos` (Patch 027): Pfad → Bytes. Nur der
  /// Betreiber liest ihn — die App hat keinen Leseweg, deshalb auch
  /// keine Fake-Methode dafür.
  final feedbackPhotoObjects = <String, Uint8List>{};
  /// Eine Zeile je Nutzer (Patch 023) — wie live_locations.
  final tourTracks = <FakeTourTrackRow>[];
  final friendships = <FakeFriendshipRow>[];
  final liveLocations = <FakeLiveShareRow>[];
  final feedback = <Map<String, dynamic>>[];

  /// Eingetragene Geräte (`push_devices`, Patch 017): Token -> Konto.
  /// Eine Zeile IST die Zustimmung dieses Geräts; es gibt bewusst kein
  /// zweites „aktiv"-Feld daneben.
  final pushDevices = <String, String?>{};

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

  /// Dasselbe für den Passwort-Reset. GoTrues Mail-Limit gilt projektweit
  /// für ALLE Mail-Sorten, nicht je Vorlage — der Fake hatte es hier
  /// trotzdem nie, und damit blieb der häufigste Fall aus dem
  /// Wochendigest untestbar.
  int passwordResetMailLimit = 100;

  /// Antwortet das Gateway gar nicht? Der Fall aus dem Digest KW39:
  /// `AuthRetryableFetchException(statusCode: 504)` aus dem Reset —
  /// dasselbe wie fehlender Empfang, nur ging die Geduld dem Gateway aus
  /// und nicht unserem Client.
  bool passwordResetTimesOut = false;

  /// Ein echter Fehler aus dem Reset — der MUSS gemeldet werden, sonst
  /// sähe niemand, wenn der Weg wirklich kaputt ist (#80).
  bool passwordResetFails = false;

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
  /// Kein Empfang beim SCHREIBEN (#267): `addSpot`/`addFinds` scheitern
  /// wie im Funkloch, und der Ausgangskorb muss übernehmen. Bleibt
  /// gesetzt, bis ein Test ihn zurücknimmt — ein Waldbesuch ist kein
  /// Einzelereignis.
  bool offline = false;

  /// Für Fakes außerhalb dieser Datei: dasselbe Funkloch.
  void failIfOffline() {
    if (offline) throw const SocketException('kein Netz (Fake)');
  }

  /// Ein Fund irgendwo im Bestand — für die Policies, die nach dem
  /// Autor fragen.
  Find? findById(String id) {
    for (final row in spots) {
      for (final f in row.finds) {
        if (f.id == id) return f;
      }
    }
    return null;
  }

  /// Der Server lehnt Schreibvorgänge ab (RLS, kaputtes Deployment). Muss
  /// sich vom Funkloch unterscheiden: Ein Serverfehler gehört NICHT in
  /// den Ausgangskorb, sonst sammelte er still Aufträge, die nie
  /// durchgehen (Lehre aus #80).
  bool rejectWrites = false;

  /// Das Gateway antwortet nicht rechtzeitig (504).
  ///
  /// Der DRITTE Fall neben [offline] und [rejectWrites], und er liegt
  /// genau dazwischen: Der Server hat nichts gesagt, also ist es kein
  /// Defekt, den man verstecken würde — aber es ist auch kein Funkloch,
  /// das Netz des Geräts trägt ja. Für die App zählt seit 1.135.0 die
  /// erste Hälfte: behandelt wie fehlender Empfang.
  bool gatewayTimeout = false;

  /// Nur der Foto-Upload scheitert, alles andere trägt — der Fall
  /// „Fund eingetragen, Foto nicht" (#532 Stufe 2).
  bool photoUploadFails = false;

  /// Kennungen (Patch 016) der Funde, die schon geschrieben wurden —
  /// spiegelt `finds_author_client_id_key`. Das Modell `Find` trägt sie
  /// nicht: Die App liest die Spalte nur beim Anlegen zurück, um die
  /// Server-id zuzuordnen — deshalb Kennung → id.
  final findClientIds = <String, String>{};

  String addSpot({
    required String ownerId,
    double lat = 51.1634,
    double lng = 10.4477,
    String? name,
    String? species,
    int? count,
    DateTime? foundOn,
    bool sharingExcluded = false,
    String? clientId,
  }) {
    final row = FakeSpotRow(
      id: _newId('spot'),
      ownerId: ownerId,
      name: name,
      lat: lat,
      lng: lng,
      sharingExcluded: sharingExcluded,
      clientId: clientId,
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
  String addFindRow(
    String spotId, {
    String? species,
    int? count,
    DateTime? foundOn,
    String? note,
    String? authorId,
    DateTime? createdAt,
    bool blank = false,
    String? clientId,
    FindPosition? position,
  }) {
    final row = spots.firstWhere((s) => s.id == spotId);
    // Spiegelt den Constraint `finds_blank_leer`: Ein Leergang trägt
    // weder Art noch Anzahl. Ohne diese Prüfung könnte ein Test einen
    // Zustand herstellen, den die Datenbank ablehnt.
    if (blank && (species != null || count != null)) {
      throw ArgumentError(
          'Ein Leergang trägt weder Art noch Anzahl (finds_blank_leer).');
    }
    // Dieselbe Rolle für `finds_position_bereich` (Patch 022). Das Paar
    // und die nicht-negative Genauigkeit kann der Fake gar nicht
    // verletzen — `FindPosition` hat dafür nur zwei Konstruktoren und ein
    // assert; hier bleibt die Grenze, die auch ein gültiger Werttyp
    // reißen kann.
    if (position != null &&
        (position.lat.abs() > 90 || position.lng.abs() > 180)) {
      throw ArgumentError(
          'Die Erde ist endlich (finds_position_bereich).');
    }
    final id = _newId('find');
    row.finds.add(Find(
      id: id,
      spotId: spotId,
      species: species,
      count: count,
      foundOn: foundOn ?? DateTime.now(),
      note: note,
      createdAt: createdAt ?? DateTime.now(),
      authorId: authorId ?? row.ownerId,
      blank: blank,
      position: position,
    ));
    if (clientId != null) findClientIds[clientId] = id;
    return id;
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

  /// Spiegel der drei finds-Policies aus Patch 014 für EINEN Betrachter
  /// — an einer Stelle, damit Spot-Abruf und Fundfotos (#532) dieselbe
  /// Antwort geben. `null` als Autor zählt als Fund des Besitzers
  /// (Zeilen von vor Patch 014).
  bool findVisibleTo(String uid, FakeSpotRow row, Find f) {
    if (row.ownerId == uid) {
      // finds_author_all + finds_owner_select: eigene immer, fremde nur
      // solange die Freigabe-Beziehung zum Autor besteht — dieselbe
      // Freundschaft, der EIGENE globale Schalter, derselbe
      // Spot-Ausschluss.
      return f.authorId == null ||
          f.authorId == uid ||
          (areFriends(uid, f.authorId!) &&
              userById(uid).shareSpotsDefault &&
              !row.sharingExcluded);
    }
    // Am Freundes-Spot: Der Spot muss sichtbar sein; von den Funden die
    // EIGENEN immer (finds_author_all), die des Besitzers nur mit dessen
    // Detail-Freigabe (finds_friend_select), die dritter Buddies nie.
    final spotVisible = areFriends(uid, row.ownerId) &&
        userById(row.ownerId).shareSpotsDefault &&
        !row.sharingExcluded;
    return spotVisible &&
        (f.authorId == uid ||
            ((f.authorId == null || f.authorId == row.ownerId) &&
                userById(row.ownerId).shareDetails));
  }

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
      throw const AuthApiException(
          'For security purposes, you can only request this after 60 seconds.',
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
    if (backend.passwordResetTimesOut) {
      throw AuthRetryableFetchException(statusCode: '504');
    }
    if (backend.passwordResetFails) {
      throw const AuthApiException('Password recovery requires an email',
          statusCode: '400', code: 'validation_failed');
    }
    final sent = backend.passwordResets.where((m) => m == email).length;
    if (sent >= backend.passwordResetMailLimit) {
      throw const AuthApiException(
          'For security purposes, you can only request this after 24 seconds.',
          statusCode: '429', code: 'over_email_send_rate_limit');
    }
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
        offsetConfirmedAt: row.offsetConfirmedAt,
        expectedSpecies: row.expectedSpecies,
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
      position: f.position,
    );
  }

  /// Setzt die Herkunft, die `fetchMySpots` meldet: nicht `null` heißt
  /// „aus dem Zwischenspeicher, von diesem Zeitpunkt" — damit sich das
  /// Offline-Banner prüfen lässt, ohne echte Dateien anzufassen.
  DateTime? cachedAt;

  /// Lässt den nächsten Abruf scheitern — für den Fall „kein Empfang und
  /// auch nichts zwischengespeichert".
  bool failNextFetch = false;

  /// Womit er scheitert. Vorgabe ist fehlender Empfang.
  ///
  /// Überschreibbar, weil der Unterschied zählt: Ein 504 ist NICHT
  /// [looksOffline], also springt in der echten App der
  /// Zwischenspeicher nicht ein und der Fehler erreicht den Aufrufer.
  /// Genau daraus entstand #371 — mit einer `SocketException` allein
  /// ließe sich der Fall gar nicht nachstellen.
  Object nextFetchError = const SocketException('kein Netz (Fake)');

  @override
  Future<SpotsSnapshot> fetchMySpots() async {
    if (failNextFetch) {
      failNextFetch = false;
      throw nextFetchError;
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
                if (backend.findVisibleTo(_uid, row, f)) _viewFind(f),
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
              offsetConfirmedAt: row.offsetConfirmedAt,
              expectedSpecies: row.expectedSpecies,
              finds: [
                for (final f in row.finds)
                  if (backend.findVisibleTo(_uid, row, f)) _viewFind(f),
              ],
            ),
      ];

  /// Spiegelt `SpotRepository.addSpot` samt der Idempotenz aus Patch 016
  /// (#267): Derselbe [clientId] legt keinen zweiten Spot an, sondern
  /// liefert den von damals. Ohne das könnte kein Test beweisen, dass
  /// eine Wiedervorlage nach abgerissener Antwort keine Dublette
  /// erzeugt — genau der Fall, für den die Spalte existiert.
  @override
  Future<String> addSpot({
    required double lat,
    required double lng,
    String? name,
    required List<NewFind> finds,
    String? clientId,
    List<String> expectedSpecies = const [],
  }) async {
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    if (backend.gatewayTimeout) {
      throw const PostgrestException(
          message: '', code: '504', details: 'Gateway Timeout');
    }
    if (backend.rejectWrites) {
      throw const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501');
    }
    if (clientId != null) {
      for (final row in backend.spots) {
        if (row.ownerId == _uid && row.clientId == clientId) {
          await addFinds(spotId: row.id, finds: finds);
          return row.id;
        }
      }
    }
    final id = backend.addSpot(
        ownerId: _uid, lat: lat, lng: lng, name: name, clientId: clientId);
    // Normalisiert wie das echte Repository (#499).
    backend.spots.firstWhere((s) => s.id == id).expectedSpecies = [
      for (final s in expectedSpecies) canonicalSpecies(s) ?? s,
    ];
    // Wie im echten Repository über addFinds, damit die Normalisierung des
    // Artnamens nur an einer Stelle steht.
    await addFinds(spotId: id, finds: finds);
    return id;
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
  Future<List<String>> addFinds({
    required String spotId,
    required List<NewFind> finds,
  }) async {
    if (finds.isEmpty) return const [];
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    if (backend.gatewayTimeout) {
      throw const PostgrestException(
          message: '', code: '504', details: 'Gateway Timeout');
    }
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
    final ids = <String>[];
    for (final find in finds) {
      // Spiegel von `finds_author_client_id_key` (Patch 016): Eine
      // Kennung, die schon steht, wird übersprungen statt doppelt
      // geschrieben. Live macht das der Unique-Index plus die
      // Nachfrage in `_unwrittenFinds`; hier ist das Ergebnis dasselbe,
      // und darauf kommt es dem Test an — die id von damals inklusive.
      final earlier = backend.findClientIds[find.clientId];
      if (earlier != null) {
        ids.add(earlier);
        continue;
      }
      ids.add(backend.addFindRow(spotId,
          species: canonicalSpecies(find.species),
          count: find.count,
          foundOn: find.foundOn,
          note: find.note,
          authorId: _uid,
          blank: find.blank,
          clientId: find.clientId,
          position: find.position));
    }
    return ids;
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
    required FindPosition? position,
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
        // Seit #466 schreibt das echte `updateFind` die drei Spalten
        // MIT, und zwar immer — auch als `null`, sonst ließe sich eine
        // Stelle nie wieder entfernen. Der Fake nimmt deshalb den
        // übergebenen Wert und NICHT `old.position`: Stünde hier weiter
        // der alte, sähe jeder Test eine Unveränderlichkeit, die es live
        // nicht mehr gibt — genau die Divergenz, die kein Schema-Check
        // bemerkt. Dass eine gemessene Stelle trotzdem stehen bleibt,
        // entscheidet das Blatt und ist dort geprüft.
        position: position,
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

  /// Spiegelt `SpotRepository.editSpot` (#466) samt der Grenze, die live
  /// `spots_owner_all` zieht: Der `using`-Teil prüft
  /// `owner_id = auth.uid()`, ein fremder Spot trifft also null Zeilen
  /// und das `.select('id')` macht daraus eine Ausnahme. Ohne diesen
  /// Nachbau bewiese ein grüner Test eine Erlaubnis, die es live nicht
  /// gibt.
  ///
  /// Die Funde bleiben ausdrücklich unangetastet — ihre absoluten
  /// Koordinaten sind eigene Messungen, der Versatz wird beim Lesen
  /// gerechnet. Genau das prüft der Flow-Test gegen.
  @override
  Future<void> editSpot({
    required String spotId,
    required String? name,
    required double lat,
    required double lng,
    bool resetOffsetConfirmation = false,
    List<String>? expectedSpecies,
  }) async {
    for (final row in backend.spots) {
      if (row.id == spotId && row.ownerId == _uid) {
        row.name = name;
        row.lat = lat;
        row.lng = lng;
        if (resetOffsetConfirmation) row.offsetConfirmedAt = null;
        if (expectedSpecies != null) {
          row.expectedSpecies = [
            for (final s in expectedSpecies) canonicalSpecies(s) ?? s,
          ];
        }
        return;
      }
    }
    throw const WriteRejectedException('Spot ändern');
  }

  /// Spiegelt `SpotRepository.pinFindsToSpot` (#475) samt der Grenze von
  /// `finds_author_all`: nur die EIGENEN Funde verlieren ihre Stelle,
  /// fremde bleiben, wo sie sind. Null Treffer sind kein Fehler.
  @override
  Future<void> pinFindsToSpot(String spotId) async {
    final row = backend.spots.firstWhere((s) => s.id == spotId);
    for (var i = 0; i < row.finds.length; i++) {
      final f = row.finds[i];
      if (f.authorId != null && f.authorId != _uid) continue;
      if (f.position == null) continue;
      row.finds[i] = Find(
        id: f.id,
        spotId: f.spotId,
        species: f.species,
        count: f.count,
        foundOn: f.foundOn,
        note: f.note,
        createdAt: f.createdAt,
        authorId: f.authorId,
        blank: f.blank,
        position: null,
      );
    }
  }

  /// Spiegelt `SpotRepository.confirmOffset` (#475) samt `spots_owner_all`:
  /// ein fremder Spot trifft null Zeilen, also Ausnahme.
  @override
  Future<void> confirmOffset(String spotId) async {
    for (final row in backend.spots) {
      if (row.id == spotId && row.ownerId == _uid) {
        row.offsetConfirmedAt = DateTime.now();
        return;
      }
    }
    throw const WriteRejectedException('Spot bestätigen');
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

class FakeTourTrackRepository implements TourTrackRepository {
  FakeTourTrackRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  @override
  Future<void> uploadMyTrack({
    required DateTime startedAt,
    required List<TourPoint> points,
    required DateTime expiresAt,
  }) async {
    // Upsert auf den Primärschlüssel `user_id` — genau EINE Zeile je
    // Nutzer, wie in Patch 023. Ein Fake, der anhinge statt zu
    // ersetzen, ließe die Zeilenzahl mit der Tour wachsen und würde
    // damit die Eigenschaft verbergen, für die die Tabelle so
    // geschnitten ist.
    final existing =
        backend.tourTracks.where((r) => r.userId == _uid).firstOrNull;
    if (existing == null) {
      backend.tourTracks.add(FakeTourTrackRow(
          userId: _uid,
          startedAt: startedAt,
          points: points,
          expiresAt: expiresAt));
    } else {
      existing
        ..startedAt = startedAt
        ..points = points
        ..expiresAt = expiresAt;
    }
  }

  @override
  Future<void> deleteMyTrack() async =>
      backend.tourTracks.removeWhere((r) => r.userId == _uid);

  /// Spiegelt `tt_friend_select`: sichtbar sind nicht abgelaufene
  /// Spuren akzeptierter Freunde, die eigene ausgeblendet. Ohne diesen
  /// Nachbau bewiese ein grüner Test eine Sichtbarkeit, die es live
  /// nicht gibt — und hier geht es um Bewegungsdaten.
  @override
  Future<List<BuddyTrack>> fetchFriendTracks() async => [
        for (final row in backend.tourTracks)
          if (row.userId != _uid &&
              backend.areFriends(_uid, row.userId) &&
              row.expiresAt.isAfter(DateTime.now().toUtc()))
            BuddyTrack(
              userId: row.userId,
              startedAt: row.startedAt,
              points: row.points,
              expiresAt: row.expiresAt,
              username: backend.userById(row.userId).username,
              avatar: backend.userById(row.userId).avatar,
            ),
      ];
}

class FakeFeedbackRepository implements FeedbackRepository {
  FakeFeedbackRepository(this.backend);

  final FakeBackend backend;

  static int _seq = 0;

  /// Spiegel von Patch 027: Objekt in den Bucket, Pfad in die Zeile —
  /// nur JPEG, nur der eigene Ordner.
  String? _store(PreparedPhoto? photo) {
    if (photo == null) return null;
    final path = '${backend.currentUserId}/feedback-${++_seq}.jpg';
    backend.feedbackPhotoObjects[path] = photo.full;
    return path;
  }

  @override
  Future<void> submit(FeedbackType type, String message,
      {String? appVersion, PreparedPhoto? photo}) async {
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    backend.feedback.add({
      'user_id': backend.currentUserId,
      'type': type == FeedbackType.bug ? 'bug' : 'feature',
      'message': message.trim(),
      'app_version': appVersion,
      'photo_path': _store(photo),
    });
  }

  @override
  Future<void> submitSpecies(String speciesName,
      {String? note, String? appVersion, PreparedPhoto? photo}) async {
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    backend.feedback.add({
      'user_id': backend.currentUserId,
      'type': 'species',
      'species_name': speciesName.trim(),
      'message': note,
      'app_version': appVersion,
      'photo_path': _store(photo),
    });
  }
}

/// Das Geräteregister (`push_devices`, Patch 017).
///
/// Bildet die eine Regel nach, auf die es ankommt: Der Token ist der
/// Schlüssel. Meldet sich am selben Gerät jemand anders an, wandert die
/// Zeile auf das neue Konto, statt daneben zu stehen — täte sie das
/// nicht, bekäme der Vorbesitzer weiter Meldungen über fremde Funde.
class FakePushRepository implements PushRepository {
  FakePushRepository(this.backend);

  final FakeBackend backend;

  /// Was hinausgegangen ist — die Tests prüfen, DASS getestet wurde,
  /// nicht wie eine Benachrichtigung aussieht.
  final tests = <String>[];

  @override
  Future<void> register(String token) async {
    backend.pushDevices[token] = backend.currentUserId;
  }

  @override
  Future<void> unregister(String token) async {
    backend.pushDevices.remove(token);
  }

  @override
  Future<void> sendTest(String token) async {
    if (backend.pushDevices[token] != backend.currentUserId) {
      // Genau das, was die Edge Function über die RLS entscheidet: Ein
      // fremdes Token geht niemanden etwas an.
      throw StateError('unknown device');
    }
    tests.add(token);
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

/// Der Fake für die großen Artbilder (#537).
///
/// **Er zählt mit, was geholt wurde.** Daran hängt die Zusage
/// „beobachten ist laden": Der Bildstreifen zeigt ein Lupensymbol, darf
/// deswegen aber nichts anstoßen — geholt wird erst beim Antippen.
/// Spiegelt `FindPhotoRepository` samt Policies aus Patch 026 (#532).
///
/// Die Sichtbarkeit einer Zeile ist die des FUNDES — genau wie live,
/// wo `fp_friend_select` nur `exists (select … from finds)` fragt. Und
/// der Bucket gibt ein Objekt nur heraus, wenn eine sichtbare Zeile dazu
/// gehört (`find_photos_read`): [loadBytes] prüft das nach, statt
/// einfach in die Map zu greifen.
class FakeFindPhotoRepository implements FindPhotoRepository {
  FakeFindPhotoRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  /// Welche Pfade abgerufen wurden — für die Zusage „aus heißt kein
  /// Download".
  final loaded = <String>[];

  /// Wo ein Fund liegt: (Spot, Fund) oder null.
  (FakeSpotRow, Find)? _locate(String findId) {
    for (final row in backend.spots) {
      for (final f in row.finds) {
        if (f.id == findId) return (row, f);
      }
    }
    return null;
  }

  bool _visible(FakeFindPhotoRow p) {
    if (p.userId == _uid) return true;
    if (!p.expiresAt.isAfter(DateTime.now().toUtc())) return false;
    final where = _locate(p.findId);
    return where != null && backend.findVisibleTo(_uid, where.$1, where.$2);
  }

  FindPhoto _view(FakeFindPhotoRow p) {
    final where = _locate(p.findId);
    final user = backend.userById(p.userId);
    return FindPhoto(
      id: p.id,
      findId: p.findId,
      userId: p.userId,
      key: p.key,
      createdAt: p.createdAt,
      expiresAt: p.expiresAt,
      isOwn: p.userId == _uid,
      username: user.username,
      avatar: user.avatar,
      species: where?.$2.species,
      foundOn: where?.$2.foundOn,
      spotId: where?.$1.id,
      spotName: where?.$1.name,
      // `fpk_select`: alle Kudos an einem Foto, das ich sehe — und dieses
      // sehe ich, sonst stünde es nicht hier.
      kudosFrom: [
        for (final k in backend.findPhotoKudos)
          if (k.photoId == p.id) k.userId,
      ],
    );
  }

  @override
  Future<void> giveKudos(String photoId) async {
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    // `fpk_insert`: nur an ein Foto, das ich sehe, und nie ans eigene.
    final photo = backend.findPhotos.where((p) => p.id == photoId).firstOrNull;
    if (photo == null || !_visible(photo) || photo.userId == _uid) {
      throw const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501');
    }
    // Der Primärschlüssel — und das Repository deutet 23505 als „steht
    // schon", der Fake nimmt das Ergebnis vorweg.
    if (backend.findPhotoKudos
        .any((k) => k.photoId == photoId && k.userId == _uid)) {
      return;
    }
    backend.findPhotoKudos.add((photoId: photoId, userId: _uid));
  }

  @override
  Future<void> takeBackKudos(String photoId) async {
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    // `fpk_delete`: nur die eigenen.
    backend.findPhotoKudos
        .removeWhere((k) => k.photoId == photoId && k.userId == _uid);
  }

  static int _seq = 0;

  @override
  Future<FindPhoto> share(
      {required String findId, required PreparedPhoto photo}) async {
    if (backend.offline || backend.photoUploadFails) {
      throw const SocketException('kein Netz (Fake)');
    }
    final key = '$_uid/fake-${++_seq}';
    // Reihenfolge wie live: erst die Objekte, dann die Zeile.
    backend.photoObjects['$key.jpg'] = photo.full;
    backend.photoObjects['${key}_s.jpg'] = photo.thumb;
    final where = _locate(findId);
    // `fp_owner_all` mit check: nur an EIGENEN Funden.
    if (where == null || (where.$2.authorId ?? _uid) != _uid) {
      backend.photoObjects.remove('$key.jpg');
      backend.photoObjects.remove('${key}_s.jpg');
      throw const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501');
    }
    final now = DateTime.now().toUtc();
    final row = FakeFindPhotoRow(
      id: 'photo-$_seq',
      findId: findId,
      userId: _uid,
      key: key,
      createdAt: now,
      expiresAt: now.add(const Duration(days: kFindPhotoDays)),
    );
    backend.findPhotos.add(row);
    return _view(row);
  }

  @override
  Future<void> delete(FindPhoto photo) async {
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    final removed = backend.findPhotos
        .where((p) => p.id == photo.id && p.userId == _uid)
        .map((p) => p.id)
        .toSet();
    backend.findPhotos.removeWhere((p) => removed.contains(p.id));
    // `on delete cascade` der Kudos.
    backend.findPhotoKudos.removeWhere((k) => removed.contains(k.photoId));
    backend.photoObjects.remove(photo.fullPath);
    backend.photoObjects.remove(photo.thumbPath);
  }

  @override
  Future<List<FindPhoto>> fetchVisible() async {
    if (backend.offline) throw const SocketException('kein Netz (Fake)');
    final rows = [
      for (final p in backend.findPhotos)
        if (_visible(p)) p
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [for (final p in rows) _view(p)];
  }

  @override
  Future<Uint8List?> loadBytes(String path) async {
    loaded.add(path);
    if (backend.offline) return null;
    final visible = backend.findPhotos
        .any((p) => _visible(p) && (path == '${p.key}.jpg' || path == '${p.key}_s.jpg'));
    return visible ? backend.photoObjects[path] : null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Was der Bildwähler liefert — steuerbar, zählend.
class FakePhotoPicker {
  FakePhotoPicker([this.next]);

  /// Die Bytes des nächsten „ausgewählten" Bildes; `null` heißt: der
  /// Nutzer bricht ab.
  Uint8List? next;
  final sources = <PhotoSource>[];

  Future<Uint8List?> call(PhotoSource source) async {
    sources.add(source);
    return next;
  }
}

class FakeSpeciesPhotos implements SpeciesPhotoRepository {
  FakeSpeciesPhotos({this.bytes});

  /// Was der Abruf liefert. `null` heißt „nicht zu holen" — der Fall
  /// ohne Empfang, in dem das mitgelieferte Bild stehen bleibt.
  final Uint8List? bytes;

  final loaded = <String>[];

  @override
  Future<Uint8List?> load(String assetPath) async {
    loaded.add(assetPath);
    return bytes;
  }

  @override
  bool get cachesToDisk => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Eine Zeile `find_reports`: wem sie gehört, und was darin steht.
typedef FakeFindReportRow = ({String userId, FindReport report});
