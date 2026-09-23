// Wohin ein Tipp auf eine Benachrichtigung führen darf (#564).
//
// **Eine Erlaubnisliste, kein Durchreichen.** Das Ziel reist als
// `data.route` in der Meldung. Die Meldungen erzeugt zwar unsere eigene
// Datenbank, aber eine Adresse, die von außen hereinkommt, bekommt nie
// ungeprüft den Router: Heute gibt es genau EIN Ziel — den Verlauf mit
// einem Buddy —, und nur dessen Form wird angenommen.

final _chatRoute = RegExp(r'^/friends/chat/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');

/// Das Ziel aus einer Meldung — `null`, wenn keines oder ein fremdes.
String? pushRouteOf(Map<String, dynamic> data) {
  final route = data['route'];
  if (route is! String || !_chatRoute.hasMatch(route)) return null;
  return route;
}
