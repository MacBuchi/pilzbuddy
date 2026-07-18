// In-Memory-Backend für Szenario-Tests: bildet Supabase-Tabellen und die
// RLS-Freigaberegeln aus supabase/schema.sql nach, damit komplette
// App-Abläufe ohne Netz und ohne Emulator in `flutter test` laufen.
//
// Wichtig: Die echten Freigaberegeln erzwingt der Server (RLS). Die Fakes
// spiegeln sie nur, damit die UI-Reaktion darauf testbar ist — sie ersetzen
// keinen RLS-Test (dafür gibt es die REST-Skripte gegen das Live-Projekt).
import 'dart:async';

import 'package:pilzbuddy/data/auth_repository.dart';
import 'package:pilzbuddy/data/feedback_repository.dart';
import 'package:pilzbuddy/data/friend_repository.dart';
import 'package:pilzbuddy/data/profile_repository.dart';
import 'package:pilzbuddy/data/spot_repository.dart';
import 'package:pilzbuddy/models/find.dart';
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
  });

  final String id;
  final String email;
  final String password;
  final String username;
  int avatar;
  bool shareSpotsDefault;
  bool shareDetails;
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

class FakeBackend {
  final users = <FakeUser>[];
  final spots = <FakeSpotRow>[];
  final friendships = <FakeFriendshipRow>[];
  final feedback = <Map<String, dynamic>>[];

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
  }) {
    final user = FakeUser(
      id: _newId('user'),
      email: email ?? '$username@test.de',
      password: password,
      username: username,
      avatar: avatar,
      shareSpotsDefault: shareSpotsDefault,
      shareDetails: shareDetails,
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

  void addFindRow(
    String spotId, {
    String? species,
    int? count,
    DateTime? foundOn,
    String? note,
  }) {
    final row = spots.firstWhere((s) => s.id == spotId);
    row.finds.add(Find(
      id: _newId('find'),
      spotId: spotId,
      species: species,
      count: count,
      foundOn: foundOn ?? DateTime.now(),
      note: note,
      createdAt: DateTime.now(),
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

  /// Test-Setup: Nutzer direkt anmelden, ohne den Login-Screen zu bedienen.
  void signInAs(String userId) => currentUserId = userId;

  FakeUser userById(String id) => users.firstWhere((u) => u.id == id);

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
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    if (backend.users.any((u) => u.username == username)) {
      // Wie in echt: der Profil-Trigger scheitert am unique-Benutzernamen.
      throw const AuthException('Database error saving new user',
          statusCode: '500');
    }
    final user =
        backend.addUser(username: username, email: email, password: password);
    // "Confirm email" ist im Supabase-Projekt aus — Signup meldet direkt an.
    backend.setCurrentUser(user, AuthChangeEvent.signedIn);
  }

  @override
  Future<void> signOut() async =>
      backend.setCurrentUser(null, AuthChangeEvent.signedOut);
}

class FakeSpotRepository implements SpotRepository {
  FakeSpotRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  Spot _toSpot(FakeSpotRow row, {required bool own, FakeUser? owner}) => Spot(
        id: row.id,
        ownerId: row.ownerId,
        name: row.name,
        lat: row.lat,
        lng: row.lng,
        sharingExcluded: row.sharingExcluded,
        isOwn: own,
        ownerUsername: owner?.username,
        ownerAvatar: owner?.avatar ?? 0,
        finds: List.of(row.finds),
      );

  @override
  Future<List<Spot>> fetchMySpots() async => [
        for (final row in backend.spots)
          if (row.ownerId == _uid) _toSpot(row, own: true),
      ];

  /// Spiegelt die RLS-Policy: sichtbar sind Spots akzeptierter Freunde,
  /// wenn deren globales Teilen an ist und der Spot nicht ausgeschlossen
  /// wurde; ohne Detail-Freigabe kommt das finds-Array leer.
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
              finds: backend.userById(row.ownerId).shareDetails
                  ? List.of(row.finds)
                  : const [],
            ),
      ];

  @override
  Future<void> addSpot({
    required double lat,
    required double lng,
    String? name,
    String? species,
    int? count,
    required DateTime foundOn,
    String? note,
  }) async {
    final id = backend.addSpot(ownerId: _uid, lat: lat, lng: lng, name: name);
    backend.addFindRow(id,
        species: species, count: count, foundOn: foundOn, note: note);
  }

  @override
  Future<void> addFind({
    required String spotId,
    String? species,
    int? count,
    required DateTime foundOn,
    String? note,
  }) async {
    backend.addFindRow(spotId,
        species: species, count: count, foundOn: foundOn, note: note);
  }

  @override
  Future<void> deleteSpot(String spotId) async =>
      backend.spots.removeWhere((s) => s.id == spotId && s.ownerId == _uid);

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
