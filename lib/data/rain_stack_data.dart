// Der Tagesstapel, wie Rechnungen ihn sehen — ohne Flutter, ohne `dart:io`.
//
// Lag bis #689 in `rain_grid_repository.dart`; der Regenverlauf und die
// Ampel rechnen damit aber auch im Web Worker des Browsers (B2), der
// ohne Flutter übersetzt wird. Das Repository exportiert diese Datei
// weiter, Aufrufer müssen nichts ändern.

/// Was das Manifest über den Tagesstapel sagt.
///
/// Alle Tage teilen sich eine Geometrie — das Werkzeug schneidet sie
/// deshalb nicht zu. Stünde sie je Tag im Manifest, wäre der erste Tag
/// mit abweichender Größe ein Verlauf, der stillschweigend den falschen
/// Punkt liest.
class RainStackInfo {
  const RainStackInfo({
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.days,
  });

  final int width;
  final int height;
  final double west;
  final double east;
  final double north;
  final double south;
  final List<RainStackDay> days;

  /// [versioned]: ob die Prüfsumme in den Namen auf Platte gehört —
  /// nur beim Alpenstapel ([RainStackKind.versioned]).
  static RainStackInfo? tryParse(Map<String, dynamic> json,
      {bool versioned = false}) {
    try {
      final days = [
        for (final day in json['days'] as List)
          RainStackDay.fromJson(day as Map<String, dynamic>,
              versioned: versioned),
      ]..sort((a, b) => a.date.compareTo(b.date));
      if (days.isEmpty) return null;
      return RainStackInfo(
        width: json['width'] as int,
        height: json['height'] as int,
        west: (json['west'] as num).toDouble(),
        east: (json['east'] as num).toDouble(),
        north: (json['north'] as num).toDouble(),
        south: (json['south'] as num).toDouble(),
        days: days,
      );
    } catch (_) {
      // Ein Manifest, das wir nicht verstehen, ist kein Grund für eine
      // Fehlermeldung — dann gibt es eben keinen Verlauf.
      return null;
    }
  }
}

/// Ein Tag des Stapels, wie das Manifest ihn nennt.
///
/// [sha256] und [origin] trägt nur der gemessene Alpenstapel (#646):
/// Dort wird ein Tag in CI NEU gemischt, sobald eine Landesquelle
/// nachkommt (GeoSphere und DPC liefern nach zwei Tagen, MeteoSchweiz
/// nach drei), und behält dabei seinen Dateinamen. Ein Zwischenspeicher,
/// der nach dem Namen geht, hielte den halb gemischten Stand für immer —
/// deshalb steht die Prüfsumme im Namen auf Platte ([cacheName]).
/// Radar- und Modelltage werden nie neu geschrieben und behalten ihren
/// Namen, obwohl auch sie eine Prüfsumme im Manifest tragen; sonst lüde
/// jedes Gerät nach dem Update beide Stapel neu.
class RainStackDay {
  const RainStackDay({
    required this.date,
    required this.file,
    this.sha256,
    this.origin,
    this.originSha256,
  });

  factory RainStackDay.fromJson(Map<String, dynamic> json,
      {bool versioned = false}) {
    final origin = json['origin'];
    return RainStackDay(
      date: DateTime.parse(json['date'] as String),
      file: json['file'] as String,
      // Radar- und Modelltage tragen im Manifest ebenfalls eine
      // Prüfsumme — sie wird dort bewusst NICHT gelesen.
      sha256: versioned ? json['sha256'] as String? : null,
      // Im Manifest ein Objekt, im gemerkten Manifest flach — beide
      // Formen lesen, damit der Weg ohne Empfang denselben Stapel sieht.
      origin: origin is Map ? origin['file'] as String? : origin as String?,
      originSha256: origin is Map
          ? origin['sha256'] as String?
          : json['origin_sha256'] as String?,
    );
  }

  final DateTime date;
  final String file;
  final String? sha256;

  /// Die Herkunftsdatei des Tages (`alps_origin_*`): je Zelle ein Bit je
  /// Quelle mit mindestens 5 % Anteil.
  final String? origin;
  final String? originSha256;

  String get cacheName => _versioned(file, sha256);
  String? get originCacheName =>
      origin == null ? null : _versioned(origin!, originSha256);

  Map<String, Object?> toJson() => {
        'date': date.toIso8601String(),
        'file': file,
        if (sha256 != null) 'sha256': sha256,
        if (origin != null) 'origin': origin,
        if (originSha256 != null) 'origin_sha256': originSha256,
      };

  static String _versioned(String file, String? sha) {
    if (sha == null || sha.length < 12) return file;
    const suffix = '.bin.gz';
    final stem = file.endsWith(suffix)
        ? file.substring(0, file.length - suffix.length)
        : file;
    return '${stem}_${sha.substring(0, 12)}$suffix';
  }
}

/// Der geladene Stapel: die Geometrie und je Tag die **gepackten** Bytes.
///
/// Gepackt mit Absicht. Entpackt wären es 14 × 752 000 Zellen, also gut
/// zehn Megabyte, die dauerhaft im Speicher lägen — in einer App, die
/// schon einmal an Speicherdruck gestorben ist (#142/#151), ist das kein
/// vertretbarer Preis für vierzehn Zahlen. Gepackt sind es 646 KB, und
/// ausgepackt wird im Isolate, ein Tag nach dem anderen.
/// Welcher Tagesstapel: das Radar des DWD (`daily`, seit 1.44.0), das
/// Modellgitter des Alpenraums (`model.rain`, seit 1.212.0, #612) oder
/// der gemessene, an den Grenzen gemischte Alpenstapel (`alps.rain`,
/// #646). Alle liegen im selben Ordner; was sie trennt, steht hier —
/// Abschnitt im Manifest, Dateianfang der Tage, Name des gemerkten
/// Manifests.
///
/// Dazu seit #676 die Bodenfeuchte (`soil`, ERA5-Land): kein Regen, aber
/// derselbe Weg — gleiches Manifest, gleiches Format, gleiches Aufräumen.
/// Ein zweiter Lader daneben wäre ein zweiter Ort, an dem ein Stand ohne
/// Empfang kleben bleibt.
enum RainStackKind {
  radar('rain_day_', 'stack.json'),
  model('model_rain_', 'model_stack.json'),
  alps('alps_', 'alps_stack.json'),
  soil('soil_', 'soil_stack.json');

  const RainStackKind(this.filePrefix, this.infoFile);

  /// Für den gemessenen Stapel `alps_` statt `alps_rain_`: Die
  /// Herkunftsdateien (`alps_origin_*`) gehören ihm ebenso, und das
  /// Aufräumen geht nach dem Anfang.
  final String filePrefix;
  final String infoFile;

  /// Ob ein Tag unter gleichem Namen neu geschrieben werden kann — dann
  /// steht seine Prüfsumme im Namen auf Platte ([RainStackDay]).
  bool get versioned => this == RainStackKind.alps;

  Map<String, dynamic>? sectionOf(Map<String, dynamic> manifest) =>
      switch (this) {
        RainStackKind.radar => manifest['daily'] as Map<String, dynamic>?,
        RainStackKind.model =>
          (manifest['model'] as Map<String, dynamic>?)?['rain']
              as Map<String, dynamic>?,
        RainStackKind.alps =>
          (manifest['alps'] as Map<String, dynamic>?)?['rain']
              as Map<String, dynamic>?,
        RainStackKind.soil => manifest['soil'] as Map<String, dynamic>?,
      };
}

class RainStackData {
  const RainStackData({
    required this.info,
    required this.days,
    this.kind = RainStackKind.radar,
    this.origins = const [],
  });

  final RainStackInfo info;
  final List<({DateTime date, List<int> gzipped})> days;

  /// Nur beim Alpenstapel: je Tag die gepackten Herkunftsbits
  /// ([alpsOriginBits]). Ein Tag ohne Herkunftsdatei hat hier keinen
  /// Eintrag — die Zahl gilt trotzdem, nur die Quellenzeile wird
  /// allgemeiner.
  final List<({DateTime date, List<int> gzipped})> origins;

  /// Welches Instrument — trägt die Herkunft bis in `RainDay.source`.
  /// Am STAPEL, nicht an seiner Position in einer Liste: Ohne Radar
  /// stünde das Modell an erster Stelle und hieße sonst „Radar".
  final RainStackKind kind;
}
