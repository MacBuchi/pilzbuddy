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

  /// Neuester Fund zuerst.
  List<Find> get findsSorted {
    final sorted = [...finds]..sort((a, b) => b.foundOn.compareTo(a.foundOn));
    return sorted;
  }

  Find? get lastFind => findsSorted.isEmpty ? null : findsSorted.first;

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
          .map((f) => Find.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'owner_id': ownerId,
        'name': name,
        'lat': lat,
        'lng': lng,
        'sharing_excluded': sharingExcluded,
      };
}
