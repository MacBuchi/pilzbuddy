import 'package:latlong2/latlong.dart';

import 'find.dart';

class Spot {
  final String id;
  final String ownerId;
  final String? name;
  final double lat;
  final double lng;
  final bool sharingExcluded;
  final bool isOwn;
  final String? ownerUsername;
  final int ownerAvatar;
  final List<Find> finds;

  const Spot({
    required this.id,
    required this.ownerId,
    this.name,
    required this.lat,
    required this.lng,
    this.sharingExcluded = false,
    this.isOwn = true,
    this.ownerUsername,
    this.ownerAvatar = 0,
    this.finds = const [],
  });

  LatLng get position => LatLng(lat, lng);

  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : 'Pilz-Spot';

  /// Alle Einträge, neuester zuerst — Funde UND Leergänge (Patch 015).
  /// Das ist die Besuchshistorie des Spots: die Fundliste im Blatt und der
  /// GPX-Export zeigen sie, weil „am 12.9. war nichts da" eine Aussage
  /// über den Spot ist.
  ///
  /// Wer über FUNDE auswertet, nimmt [findsSorted] / [ownFinds] — die
  /// sieben Leergänge aus. Das ist die Trennlinie, an der Statistik,
  /// Marker-Icon, Art-Filter und Buddy-Banner hängen.
  List<Find> get entriesSorted {
    final sorted = [...finds]..sort((a, b) => b.foundOn.compareTo(a.foundOn));
    return sorted;
  }

  /// Neuester Fund zuerst — **ohne Leergänge**.
  List<Find> get findsSorted => [
        for (final find in entriesSorted)
          if (!find.blank) find,
      ];

  /// Neuester Fund ÜBERHAUPT — egal von wem. Bewusst die Quelle für
  /// Marker-Icon, Blattkopf und Synonymzeile: Sie beschreiben den Spot,
  /// nicht die Autorschaft. Wo es um MEINE Daten geht (Vorbelegung,
  /// Statistik, GPX-Export), gilt stattdessen [lastOwnFind]/[ownFinds].
  Find? get lastFind => findsSorted.isEmpty ? null : findsSorted.first;

  /// Alle eigenen Einträge inklusive Leergänge (seit Patch 014 können an
  /// geteilten Spots auch Buddies eintragen). Für den GPX-Export: Ein
  /// Leergang ist erhebenswerte eigene Beobachtung, sonst wäre der Export
  /// nicht mehr verlustfrei (#112).
  List<Find> get ownEntries => [
        for (final find in finds)
          if (find.isOwn) find,
      ];

  /// Nur die eigenen FUNDE — ohne Leergänge. Grundlage von Statistik und
  /// Art-Vorschlägen.
  List<Find> get ownFinds => [
        for (final find in ownEntries)
          if (!find.blank) find,
      ];

  /// Neuester EIGENER Fund — die richtige Vorbelegung für „Fund
  /// eintragen": Am Freundes-Spot soll nicht dessen letzter Fund im
  /// Formular stehen.
  Find? get lastOwnFind {
    final own = ownFinds..sort((a, b) => b.foundOn.compareTo(a.foundOn));
    return own.isEmpty ? null : own.first;
  }

  Spot copyWith({
    String? name,
    bool? sharingExcluded,
    List<Find>? finds,
  }) =>
      Spot(
        id: id,
        ownerId: ownerId,
        name: name ?? this.name,
        lat: lat,
        lng: lng,
        sharingExcluded: sharingExcluded ?? this.sharingExcluded,
        isOwn: isOwn,
        ownerUsername: ownerUsername,
        ownerAvatar: ownerAvatar,
        finds: finds ?? this.finds,
      );

  factory Spot.fromJson(Map<String, dynamic> json, {required String currentUserId}) {
    final findsJson = json['finds'] as List<dynamic>? ?? const [];
    return Spot(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      sharingExcluded: json['sharing_excluded'] as bool? ?? false,
      isOwn: json['owner_id'] == currentUserId,
      ownerUsername:
          (json['profiles'] as Map<String, dynamic>?)?['username'] as String?,
      ownerAvatar:
          (json['profiles'] as Map<String, dynamic>?)?['avatar'] as int? ?? 0,
      finds: findsJson
          .map((f) => Find.fromJson(f as Map<String, dynamic>,
              currentUserId: currentUserId))
          .toList(),
    );
  }

}
