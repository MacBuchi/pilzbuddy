import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dates.dart';
import '../core/errors.dart';
import '../core/mushroom_species.dart';
import '../models/spot.dart';
import 'session.dart';
import 'spot_cache.dart';

/// Die eigenen Spots samt Herkunft: `cachedAt == null` heißt frisch aus
/// dem Netz, sonst stammen sie aus dem Zwischenspeicher und sind von
/// diesem Zeitpunkt.
typedef SpotsSnapshot = ({List<Spot> spots, DateTime? cachedAt});

/// Ein zu schreibender Eintrag — der Transporttyp ALLER Schreibwege:
/// Fund-Blatt, Anlege-Blatt und GPX-Import.
///
/// Eigener Typ und nicht `ImportedFind` aus `features/import_export/`:
/// Die Datenschicht kennt keine Features. Dass beide dieselben Felder
/// tragen, ist der Punkt — hier endet der Import und beginnt die
/// Datenbank.
///
/// Eine Klasse und kein Record, weil die Bedingung aus [blank] mitgeprüft
/// werden soll: Ein Leergang mit Artangabe wäre live ein
/// Constraint-Verstoß (`finds_blank_leer`, Patch 015), und der soll nicht
/// erst beim Insert auffallen.
class NewFind {
  final String? species;
  final int? count;
  final DateTime foundOn;
  final String? note;

  /// „Nichts gefunden" — siehe `Find.blank` in `models/find.dart`.
  final bool blank;

  /// Vom Gerät vergebene Kennung (Patch 016, #267). Gesetzt für alles,
  /// was über den Ausgangskorb läuft — sie macht eine Wiedervorlage nach
  /// einem abgerissenen Insert idempotent. `null` bei allen anderen
  /// Wegen (GPX-Import etwa läuft im WLAN und kennt keinen Korb).
  final String? clientId;

  const NewFind({
    this.species,
    this.count,
    required this.foundOn,
    this.note,
    this.blank = false,
    this.clientId,
  }) : assert(!blank || (species == null && count == null),
            'Ein Leergang trägt weder Art noch Anzahl (finds_blank_leer).');

  /// „War da, nichts da." Bewusst ohne Art: Die Aussage gilt dem Ort.
  const NewFind.blank(
      {required DateTime foundOn, String? note, String? clientId})
      : this(
            foundOn: foundOn, note: note, blank: true, clientId: clientId);

  NewFind withClientId(String clientId) => NewFind(
        species: species,
        count: count,
        foundOn: foundOn,
        note: note,
        blank: blank,
        clientId: clientId,
      );
}

/// Ein Spot samt Einträgen, wie ihn der GPX-Import wiederherstellt.
typedef RestorableSpot = ({
  double lat,
  double lng,
  String? name,
  bool sharingExcluded,
  List<NewFind> finds,
});

class SpotRepository {
  SpotRepository(this._client, {SpotCache? cache}) : _cache = cache;

  final SupabaseClient _client;
  final SpotCache? _cache;

  /// Nach dieser Zeit gilt der Abruf als gescheitert und der
  /// Zwischenspeicher übernimmt.
  ///
  /// Nötig, weil postgrest GET-Anfragen von sich aus dreimal wiederholt
  /// (Backoff 1+2+4 s). Ohne Deckel wartet die Karte im Funkloch alle
  /// vier Versuche ab — und bei „ein Balken, keine Daten" hängt jeder
  /// davon am Zeitlimit des Systems, was Minuten bedeuten kann. Genau
  /// dann soll die Offline-Kopie zügig einspringen.
  static const fetchTimeout = Duration(seconds: 10);

  String get _uid => _client.requireUid;

  /// Eigene Spots. Ohne Empfang kommen sie aus dem Zwischenspeicher —
  /// siehe `spot_cache.dart` für den Grund.
  Future<SpotsSnapshot> fetchMySpots() async {
    final uid = _uid;
    Future<List<Map<String, dynamic>>> fetch() async {
      // Der Autor kommt als benannter Embed über den FK-Namen mit —
      // seit Patch 014 können auch Buddies an eigenen Spots Funde haben,
      // und die Fundliste nennt dann, von wem einer stammt.
      final rows = await _client
          .from('spots')
          .select(
              '*, finds(*, author:profiles!finds_author_id_fkey(username, avatar))')
          .eq('owner_id', uid)
          .order('created_at')
          .timeout(fetchTimeout);
      return rows.cast<Map<String, dynamic>>();
    }

    final cache = _cache;
    final result = cache == null
        ? (rows: await fetch(), cachedAt: null)
        : await fetchSpotRowsWithCache(
            fetch: fetch,
            cache: cache,
            uid: uid,
            now: DateTime.now(),
          );
    return (
      spots: [
        for (final row in result.rows) Spot.fromJson(row, currentUserId: uid),
      ],
      cachedAt: result.cachedAt,
    );
  }

  /// Von Freunden geteilte Spots. Die RLS-Policies liefern nur, was der
  /// jeweilige Besitzer freigegeben hat; ohne Detail-Freigabe kommen von
  /// seinen Funden keine — die EIGENEN am Freundes-Spot liefert
  /// `finds_author_all` immer (Patch 014).
  Future<List<Spot>> fetchFriendSpots() async {
    final rows = await _client
        .from('spots')
        .select(
            '*, finds(*, author:profiles!finds_author_id_fkey(username, avatar)), profiles(username, avatar)')
        .neq('owner_id', _uid);
    return rows.map((r) => Spot.fromJson(r, currentUserId: _uid)).toList();
  }

  /// Neuer Spot samt seiner ersten Einträge. Mehrere, weil an einem Ort
  /// mehrere Arten stehen können (#211) — der Sammler im Anlege-Blatt gibt
  /// sie in einem Rutsch her.
  ///
  /// Liefert die id des Spots: Der Ausgangskorb (#267) braucht sie, um
  /// wartende Funde aufzulösen, die an diesem noch nicht gesendeten Spot
  /// hängen.
  ///
  /// [clientId] macht den Aufruf **wiederholbar** (Patch 016): Reißt die
  /// Verbindung nach dem Insert ab, sieht der Aufrufer einen Fehler,
  /// obwohl die Zeile steht. Der zweite Anlauf läuft dann in den
  /// Unique-Index und findet über [_existingSpotId] die id von vorhin,
  /// statt einen zweiten Spot an denselben Fleck zu setzen.
  Future<String> addSpot({
    required double lat,
    required double lng,
    String? name,
    required List<NewFind> finds,
    String? clientId,
  }) async {
    String spotId;
    try {
      final spot = await _client
          .from('spots')
          .insert({
            'owner_id': _uid,
            'name': name,
            'lat': lat,
            'lng': lng,
            'client_id': ?clientId,
          })
          .select('id')
          .single();
      spotId = spot['id'] as String;
    } on PostgrestException catch (error) {
      final existing = await _existingSpotId(error, clientId);
      if (existing == null) rethrow;
      spotId = existing;
    }
    await addFinds(spotId: spotId, finds: finds);
    return spotId;
  }

  /// Die id des Spots, den ein früherer Anlauf schon angelegt hat — oder
  /// `null`, wenn dieser Fehler nichts damit zu tun hat.
  ///
  /// `23505` ist der Unique-Verstoß aus `spots_owner_client_id_key`. Er
  /// kann hier NUR von einer Wiederholung kommen: Die Kennung entsteht
  /// je Auftrag neu und verlässt das Gerät sonst nicht.
  Future<String?> _existingSpotId(
      PostgrestException error, String? clientId) async {
    if (error.code != '23505' || clientId == null) return null;
    final rows = await _client
        .from('spots')
        .select('id')
        .eq('owner_id', _uid)
        .eq('client_id', clientId)
        .limit(1);
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  /// Stellt einen Spot samt seiner Funde wieder her — der Weg für den
  /// verlustfreien GPX-Import (#112).
  ///
  /// Eigene Methode und nicht [addSpot], weil dort `sharing_excluded`
  /// nicht vorkommt und ein Spot ganz ohne Eintrag unmöglich wäre. Beide
  /// Fälle gehören zu einer Sicherung.
  ///
  /// `created_at` setzt der Server neu. Das ist Absicht — `found_on` ist
  /// das biologische Datum und die Größe, an der später gerechnet wird
  /// (#199); wann die Zeile eingefügt wurde, ist keine Eigenschaft des
  /// Fundes.
  Future<void> restoreSpot({
    required double lat,
    required double lng,
    String? name,
    bool sharingExcluded = false,
    required List<NewFind> finds,
  }) async {
    final spot = await _client
        .from('spots')
        .insert({
          'owner_id': _uid,
          'name': name,
          'lat': lat,
          'lng': lng,
          'sharing_excluded': sharingExcluded,
        })
        .select('id')
        .single();
    await addFinds(spotId: spot['id'] as String, finds: finds);
  }

  /// Legt Einträge an einem Spot an. Der Artname wird dabei auf die
  /// Hauptbezeichnung gebracht ([canonicalSpecies]) — „Totentrompete" wird
  /// als „Herbsttrompete" gespeichert. Damit liegen in der Datenbank keine
  /// zwei Namen für dieselbe Art nebeneinander; eigene Arten der Nutzer
  /// bleiben unverändert.
  ///
  /// **Die einzige Schreibstelle für Funde** — [addSpot], [restoreSpot]
  /// und das Fund-Blatt laufen alle hier durch. Vorher gab es zwei, und
  /// die Normalisierung musste an beiden stehen.
  ///
  /// Alles geht in **einem** Insert raus: Drei Arten an einem Spot (#211)
  /// oder ein importierter Spot mit zwanzig Funden wären sonst ebenso
  /// viele Rundreisen.
  ///
  /// `author_id` wird bewusst NICHT mitgesendet: Der Spalten-Default
  /// `auth.uid()` füllt ihn serverseitig (Patch 014) — derselbe Weg, den
  /// auch ältere Clients nehmen, die die Spalte gar nicht kennen.
  Future<void> addFinds({
    required String spotId,
    required List<NewFind> finds,
  }) async {
    if (finds.isEmpty) return;
    try {
      await _client.from('finds').insert(_findRows(spotId, finds));
    } on PostgrestException catch (error) {
      final remaining = await _unwrittenFinds(error, finds);
      if (remaining == null) rethrow;
      if (remaining.isEmpty) return; // Ein früherer Anlauf war vollständig.
      await _client.from('finds').insert(_findRows(spotId, remaining));
    }
  }

  List<Map<String, dynamic>> _findRows(String spotId, List<NewFind> finds) => [
        for (final find in finds)
          {
            'spot_id': spotId,
            'species': canonicalSpecies(find.species),
            'count': find.count,
            'found_on': isoDate(find.foundOn),
            'note': find.note,
            'blank': find.blank,
            if (find.clientId != null) 'client_id': find.clientId,
          },
      ];

  /// Welche dieser Einträge ein früherer Anlauf noch NICHT geschrieben
  /// hat — `null`, wenn dieser Fehler nichts mit einer Wiederholung zu
  /// tun hat und weitergereicht gehört.
  ///
  /// Der Batch-Insert ist alles oder nichts: Steht auch nur eine Zeile
  /// schon, scheitert der ganze Aufruf. Deshalb wird hier gefragt, was
  /// wirklich fehlt, statt den Fehler pauschal zu schlucken — sonst
  /// verlöre eine Wiedervorlage die übrigen Funde desselben Auftrags.
  Future<List<NewFind>?> _unwrittenFinds(
      PostgrestException error, List<NewFind> finds) async {
    if (error.code != '23505') return null;
    final ids = [
      for (final find in finds)
        if (find.clientId != null) find.clientId!,
    ];
    // Ohne Kennung an JEDEM Eintrag ist nicht entscheidbar, welcher schon
    // steht — dann ist der Verstoß nicht unserer.
    if (ids.length != finds.length) return null;
    final rows = await _client
        .from('finds')
        .select('client_id')
        .eq('author_id', _uid)
        .inFilter('client_id', ids);
    final written = {for (final row in rows) row['client_id'] as String};
    if (written.isEmpty) return null;
    return [
      for (final find in finds)
        if (!written.contains(find.clientId)) find,
    ];
  }

  /// Ändert einen einzelnen Eintrag (#240): der Weg, einen Vertipper in
  /// der Art, ein falsches Datum oder eine Notiz zu korrigieren, ohne den
  /// ganzen Spot samt Historie zu löschen.
  ///
  /// Braucht KEINEN neuen Patch: `finds_author_all` (Patch 014) ist `for
  /// all` mit `using (author_id = auth.uid())` — Ändern und Löschen
  /// eigener Funde waren seit jeher erlaubt, nur nie benutzt.
  ///
  /// `spot_id` bleibt außen vor: Ein Fund wandert nicht per Korrektur an
  /// einen anderen Ort, dafür gibt es [mergeSpots].
  ///
  /// Die Normalisierung läuft wie beim Anlegen ([addFinds]) über
  /// [canonicalSpecies] — sonst entstünden über den Korrekturweg
  /// Schreibweisen, die der Anlegeweg nie erzeugt.
  Future<void> updateFind({
    required String findId,
    required NewFind find,
  }) async {
    final rows = await _client
        .from('finds')
        .update({
          'species': canonicalSpecies(find.species),
          'count': find.count,
          'found_on': isoDate(find.foundOn),
          'note': find.note,
          'blank': find.blank,
        })
        .eq('id', findId)
        // `.select()` ist hier keine Zierde, sondern die einzige
        // Rückmeldung: Trifft die Anfrage wegen RLS keine Zeile, ist das
        // für PostgREST kein Fehler — ohne die zurückgegebene Liste
        // meldete die App Erfolg für einen Vorgang, der nie stattfand.
        .select('id');
    if (rows.isEmpty) throw const WriteRejectedException('Fund ändern');
  }

  /// Löscht einen einzelnen Eintrag (#240).
  ///
  /// Anders als [updateFind] gelingt das auch an einem Freundes-Spot,
  /// dessen Freigabe endet: Das `using` von `finds_author_all` fragt nur
  /// nach dem Autor, der `with check` mit dem Spot-Zugang gilt allein
  /// fürs Schreiben. Wer seine Daten zurückziehen will, kann das also
  /// immer.
  Future<void> deleteFind(String findId) async {
    final rows =
        await _client.from('finds').delete().eq('id', findId).select('id');
    if (rows.isEmpty) throw const WriteRejectedException('Fund löschen');
  }

  Future<void> deleteSpot(String spotId) async {
    await _client.from('spots').delete().eq('id', spotId);
  }

  /// Führt zwei eigene Spots zusammen (#215): Die Funde von [fromId]
  /// wandern nach [intoId], danach verschwindet [fromId].
  ///
  /// **Reihenfolge ist hier alles.** Erst umhängen, dann löschen — die
  /// umgekehrte Folge löscht die Funde mit
  /// (`finds.spot_id … on delete cascade`), und danach gibt es nichts mehr
  /// umzuhängen. Schlägt das Löschen fehl, stehen die Funde bereits am
  /// Ziel und der leere Quell-Spot bleibt übrig: sichtbar und von Hand
  /// löschbar, also der harmlosere der beiden Halbzustände.
  ///
  /// **Fremde Funde wandern nicht mit.** `finds_author_all` erlaubt das
  /// Update nur für `author_id = auth.uid()`; ein Buddy-Fund bliebe still
  /// liegen und fiele beim Löschen der Kaskade zum Opfer. Deshalb bietet
  /// die Oberfläche solche Paare gar nicht erst an (`canMerge` in
  /// `features/spots/nearby_spots.dart`) — hier steht der Grund, warum
  /// diese Methode sich darauf verlassen darf.
  Future<void> mergeSpots(
      {required String intoId, required String fromId}) async {
    await _client
        .from('finds')
        .update({'spot_id': intoId}).eq('spot_id', fromId);
    await deleteSpot(fromId);
  }

  Future<void> setSharingExcluded(String spotId, bool excluded) async {
    await _client
        .from('spots')
        .update({'sharing_excluded': excluded}).eq('id', spotId);
  }
}
