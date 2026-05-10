/// Winter alert model — one CAP-class active alert from
/// the NOAA / NWS `/alerts/active` endpoint.
///
/// Fields mirror the GeoJSON `features[].properties` shape returned by
/// `api.weather.gov`. Only fields relevant to winter-driving consumers are
/// surfaced here; other CAP fields (parameters, references, geocode, etc.)
/// are intentionally not modelled in this smallest-slice.
library;

import 'package:equatable/equatable.dart';

/// The 14 winter event types catalogued at
/// `api.weather.gov/alerts/types`. Used to filter
/// the unfiltered `/alerts/active` response down to winter scope.
///
/// Verbatim strings from the NWS API (matching the `event` field exactly).
const Set<String> kNwsWinterEventTypes = <String>{
  'Winter Storm Warning',
  'Winter Storm Watch',
  'Winter Weather Advisory',
  'Blizzard Warning',
  'Ice Storm Warning',
  'Heavy Freezing Spray Warning',
  'Heavy Freezing Spray Watch',
  'Lake Effect Snow Warning',
  'Freeze Warning',
  'Freeze Watch',
  'Freezing Fog Advisory',
  'Cold Weather Advisory',
  'Extreme Cold Warning',
  'Extreme Cold Watch',
};

/// CAP severity classification (per NWS GeoJSON `severity` field).
enum AlertSeverity { unknown, minor, moderate, severe, extreme }

/// CAP certainty classification (per NWS GeoJSON `certainty` field).
enum AlertCertainty { unknown, unlikely, possible, likely, observed }

/// CAP urgency classification (per NWS GeoJSON `urgency` field).
enum AlertUrgency { unknown, past, future, expected, immediate }

/// CAP message-type (per NWS GeoJSON `messageType` field).
///
/// `Alert` = initial issuance; `Update` = revision; `Cancel` = revoked
/// before expiry. Consumers typically present the most recent for a
/// given identifier chain.
enum AlertMessageType { unknown, alert, update, cancel }

/// CAP status (per NWS GeoJSON `status` field).
///
/// `Actual` = real-world event; `Exercise`, `System`, `Test`, `Draft`
/// are non-real-world classifications a driver-facing consumer should
/// suppress. Default behaviour in [NoaaNwsClient] keeps only `Actual`.
enum AlertStatus { unknown, actual, exercise, system, test, draft }

/// A WGS84 latitude/longitude pair, immutable and equatable.
///
/// Used as the vertex shape for [WinterAlertArea.polygon] and
/// [WinterAlertCircle.center]. We do not depend on `latlong2` here to
/// keep the `noaa_nws_adapter` package boundary narrow (smallest-slice
/// discipline); integrators wishing to hand off to a geometry library
/// translate at their boundary.
class GeoPoint extends Equatable {
  /// Decimal degrees latitude (WGS84). Range: -90 to 90.
  final double latitude;

  /// Decimal degrees longitude (WGS84). Range: -180 to 180.
  final double longitude;

  const GeoPoint({required this.latitude, required this.longitude});

  @override
  List<Object?> get props => <Object?>[latitude, longitude];

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// One circle as expressed in the CAP `area/circle` element:
/// a center [GeoPoint] plus a radius in kilometres.
///
/// Driver-facing rationale: when the publisher describes the alert
/// area as a circle (e.g. severe-weather impact radius around a
/// reference point), the consumer can present a precise geographic
/// scope to the driver rather than an abstract zone identifier.
class WinterAlertCircle extends Equatable {
  /// Center of the circle (WGS84 decimal degrees).
  final GeoPoint center;

  /// Radius of the circle in kilometres. Per CAP spec the value is
  /// always non-negative.
  final double radiusKm;

  const WinterAlertCircle({required this.center, required this.radiusKm});

  @override
  List<Object?> get props => <Object?>[center, radiusKm];

  @override
  String toString() =>
      'WinterAlertCircle(center: $center, radiusKm: $radiusKm)';
}

/// Typed geographic-area record for a [WinterAlert].
///
/// At least one of [polygon] / [circle] is non-null when the publisher
/// declared a CAP `area/polygon` or `area/circle`; both null when the
/// publisher only declared a free-form area description (in which case
/// the prose lives in [WinterAlert.areaDesc]).
///
/// Driver-facing loom: *"winter alert covers a precise geographic area
/// on the route, not just an abstract zone identifier."* The polygon
/// shape supports the integrator's per-route geofence-class question
/// "does this alert intersect my route?" without flying out to a
/// gazetteer service.
class WinterAlertArea extends Equatable {
  /// Polygon vertices in publisher order. Empty when the publisher did
  /// not declare a polygon. CAP polygons are "closed" — the first and
  /// last vertices are typically equal; we preserve the publisher's
  /// vertex list verbatim without de-duplicating.
  final List<GeoPoint> polygon;

  /// Circle declaration when the publisher used the CAP `area/circle`
  /// shape; null when the publisher did not declare a circle.
  final WinterAlertCircle? circle;

  const WinterAlertArea({this.polygon = const <GeoPoint>[], this.circle});

  /// True when the publisher declared neither polygon nor circle. The
  /// caller can fall back to [WinterAlert.areaDesc] for free-form
  /// area prose.
  bool get isEmpty => polygon.isEmpty && circle == null;

  @override
  List<Object?> get props => <Object?>[polygon, circle];

  @override
  String toString() =>
      'WinterAlertArea(polygon: ${polygon.length} vertices, '
      'circle: $circle)';
}

/// One active winter alert. Equatable for stream de-duplication.
///
/// All fields are non-null in the model; missing GeoJSON properties are
/// resolved to `unknown` for enums or empty string for free-form strings,
/// with the notable exception of the timestamp pair which preserve
/// nullability since `effective` and `expires` may legitimately be
/// absent on some alert types per the CAP spec.
class WinterAlert extends Equatable {
  /// Verbatim NWS event type, e.g. `Winter Storm Warning`. Always one of
  /// [kNwsWinterEventTypes] when constructed via [NoaaNwsClient].
  final String event;

  /// CAP severity. `unknown` if the source omitted the field.
  final AlertSeverity severity;

  /// CAP certainty. `unknown` if the source omitted the field.
  final AlertCertainty certainty;

  /// CAP urgency. `unknown` if the source omitted the field.
  final AlertUrgency urgency;

  /// Free-form area description, e.g.
  /// `Towner; Cavalier; Benson; Ramsey; ...`.
  final String areaDesc;

  /// When the alert is in force.
  final DateTime? effective;

  /// When the alert expires.
  final DateTime? expires;

  /// Short human-readable summary, e.g.
  /// `Winter Storm Warning issued ... by NWS Grand Forks ND`.
  final String headline;

  /// Multi-paragraph description of the meteorological situation.
  final String description;

  /// Public-safety guidance, often empty for advisory classes.
  final String instruction;

  /// CAP status. `unknown` if the source omitted the field.
  final AlertStatus status;

  /// CAP message-type. `unknown` if the source omitted the field.
  final AlertMessageType messageType;

  /// Issuing office, e.g. `NWS Grand Forks ND`.
  final String senderName;

  /// Typed geographic-area record parsed from the NWS GeoJSON
  /// `geometry` envelope (top-level `Polygon`/`MultiPolygon`/`Point`
  /// shape) and/or CAP-class area sub-elements. `null` when the
  /// feature lacked a parseable geometry — in that case the
  /// publisher's free-form prose in [areaDesc] is the only area
  /// substrate.
  ///
  /// **Added in 0.0.3** (additive; back-compat preserved). Previous
  /// versions did not surface a typed area. Construction without
  /// `area` is permitted; callers using [WinterAlert.fromProperties]
  /// see `area: null` (the properties dict alone does not carry
  /// geometry); callers using [WinterAlert.fromFeature] receive the
  /// parsed typed area.
  final WinterAlertArea? area;

  const WinterAlert({
    required this.event,
    required this.severity,
    required this.certainty,
    required this.urgency,
    required this.areaDesc,
    required this.effective,
    required this.expires,
    required this.headline,
    required this.description,
    required this.instruction,
    required this.status,
    required this.messageType,
    required this.senderName,
    this.area,
  });

  /// True if this alert's `event` string is one of the catalogued
  /// winter event types.
  bool get isWinterEvent => kNwsWinterEventTypes.contains(event);

  /// True if this alert is severe or extreme — driver-actionable
  /// signal class.
  bool get isHighImpact =>
      severity == AlertSeverity.severe || severity == AlertSeverity.extreme;

  /// True if this alert is `Actual` (i.e. not exercise / test / draft).
  bool get isActual => status == AlertStatus.actual;

  @override
  List<Object?> get props => <Object?>[
    event,
    severity,
    certainty,
    urgency,
    areaDesc,
    effective,
    expires,
    headline,
    description,
    instruction,
    status,
    messageType,
    senderName,
    area,
  ];

  @override
  String toString() =>
      'WinterAlert(event: $event, severity: ${severity.name}, '
      'area: $areaDesc, effective: $effective, expires: $expires)';

  /// Builds a [WinterAlert] from one GeoJSON feature `properties` map.
  ///
  /// Throws [NoaaNwsParseException] when the `event` field is missing or
  /// not a String. Other missing fields resolve to defaults rather than
  /// throw, so a partial response yields usable (if abbreviated) records.
  ///
  /// Returns a record with `area: null` — the properties dict alone does
  /// not carry the polygon (NWS GeoJSON places it on the top-level
  /// feature `geometry`). Use [WinterAlert.fromFeature] when the typed
  /// area is needed.
  ///
  /// Visible for testing — allows direct invocation without HTTP.
  static WinterAlert fromProperties(Map<String, dynamic> properties) {
    final eventRaw = properties['event'];
    if (eventRaw is! String) {
      throw const NoaaNwsParseException(
        "GeoJSON feature 'properties.event' missing or not a String",
      );
    }
    return WinterAlert(
      event: eventRaw,
      severity: _parseSeverity(properties['severity']),
      certainty: _parseCertainty(properties['certainty']),
      urgency: _parseUrgency(properties['urgency']),
      areaDesc: _readString(properties, 'areaDesc'),
      effective: _readDateTime(properties, 'effective'),
      expires: _readDateTime(properties, 'expires'),
      headline: _readString(properties, 'headline'),
      description: _readString(properties, 'description'),
      instruction: _readString(properties, 'instruction'),
      status: _parseStatus(properties['status']),
      messageType: _parseMessageType(properties['messageType']),
      senderName: _readString(properties, 'senderName'),
    );
  }

  /// Builds a [WinterAlert] from one GeoJSON feature object (the full
  /// envelope with `properties` AND `geometry`).
  ///
  /// Compared to [WinterAlert.fromProperties]: identical field
  /// extraction from `properties`, additionally parsing the top-level
  /// `geometry` into a typed [WinterAlertArea].
  ///
  /// Geometry support:
  /// - `geometry: null` → `area = null`.
  /// - `geometry: { type: 'Polygon', coordinates: [[[lng,lat], ...]] }`
  ///   → `area.polygon = [GeoPoint, ...]` (first ring; CAP polygons
  ///   are simple closed shapes).
  /// - `geometry: { type: 'MultiPolygon', coordinates: [[[[lng,lat], ...]]] }`
  ///   → `area.polygon` collects vertices from the first polygon's
  ///   first ring (sufficient for the smallest-slice geofence-class
  ///   question; multi-polygon-fidelity callers are encouraged to
  ///   parse the raw GeoJSON themselves).
  /// - Any other geometry type (`Point`, `LineString`, etc.) →
  ///   `area = WinterAlertArea()` empty (caller falls back to
  ///   [areaDesc]).
  ///
  /// CAP `area/circle` is also surfaced from `properties.parameters`
  /// when the publisher used the CAP shape (rare in NWS GeoJSON; more
  /// common in CAP-XML).
  static WinterAlert fromFeature(Map<String, dynamic> feature) {
    final propsRaw = feature['properties'];
    if (propsRaw is! Map<String, dynamic>) {
      throw const NoaaNwsParseException(
        "GeoJSON feature 'properties' missing or not a JSON object",
      );
    }
    final base = fromProperties(propsRaw);
    final area = parseArea(feature['geometry'], propsRaw['parameters']);
    return WinterAlert(
      event: base.event,
      severity: base.severity,
      certainty: base.certainty,
      urgency: base.urgency,
      areaDesc: base.areaDesc,
      effective: base.effective,
      expires: base.expires,
      headline: base.headline,
      description: base.description,
      instruction: base.instruction,
      status: base.status,
      messageType: base.messageType,
      senderName: base.senderName,
      area: area,
    );
  }

  /// Parses an NWS GeoJSON geometry value (and optional CAP parameters
  /// dict) into a typed [WinterAlertArea]. Returns null when the
  /// publisher declared neither a parseable geometry nor a CAP circle.
  ///
  /// Visible for direct testing.
  static WinterAlertArea? parseArea(Object? geometry, Object? parameters) {
    final polygonVertices = _parseGeometryPolygon(geometry);
    final circle = _parseCircleFromParameters(parameters);
    if (polygonVertices.isEmpty && circle == null) {
      return null;
    }
    return WinterAlertArea(polygon: polygonVertices, circle: circle);
  }
}

/// Parses a GeoJSON `geometry` object's first-ring polygon vertices into
/// a list of [GeoPoint]. Returns an empty list when geometry is null /
/// non-polygon / malformed.
List<GeoPoint> _parseGeometryPolygon(Object? geometry) {
  if (geometry is! Map<String, dynamic>) return const <GeoPoint>[];
  final type = geometry['type'];
  final coordinates = geometry['coordinates'];
  if (type == 'Polygon') {
    return _readFirstRing(coordinates);
  }
  if (type == 'MultiPolygon') {
    if (coordinates is! List || coordinates.isEmpty) {
      return const <GeoPoint>[];
    }
    final firstPolygon = coordinates.first;
    return _readFirstRing(firstPolygon);
  }
  return const <GeoPoint>[];
}

/// Reads the first linear ring of a GeoJSON polygon coordinates value:
/// `[[[lng,lat], [lng,lat], ...], ...]` → `[GeoPoint, ...]`.
List<GeoPoint> _readFirstRing(Object? polygonCoords) {
  if (polygonCoords is! List || polygonCoords.isEmpty) {
    return const <GeoPoint>[];
  }
  final firstRing = polygonCoords.first;
  if (firstRing is! List) return const <GeoPoint>[];
  final out = <GeoPoint>[];
  for (final pt in firstRing) {
    if (pt is! List || pt.length < 2) continue;
    final lng = pt[0];
    final lat = pt[1];
    if (lng is! num || lat is! num) continue;
    out.add(GeoPoint(latitude: lat.toDouble(), longitude: lng.toDouble()));
  }
  return out;
}

/// Parses a CAP-class `area/circle` declaration from a NWS GeoJSON
/// `parameters` dict, when present. Returns null when no circle is
/// declared.
///
/// CAP `circle` text is `"<lat>,<lon> <radius_km>"`. The dict shape may
/// be `parameters['circle']: ['<text>']` (NWS GeoJSON commonly arrays
/// scalar values); we accept either a single-string or single-element
/// list.
WinterAlertCircle? _parseCircleFromParameters(Object? parameters) {
  if (parameters is! Map<String, dynamic>) return null;
  final raw = parameters['circle'];
  String? text;
  if (raw is String) {
    text = raw;
  } else if (raw is List && raw.isNotEmpty && raw.first is String) {
    text = raw.first as String;
  }
  if (text == null || text.isEmpty) return null;
  // "<lat>,<lon> <radius_km>" — lat,lon comma-separated, then radius.
  final parts = text.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final centerParts = parts[0].split(',');
  if (centerParts.length != 2) return null;
  final lat = double.tryParse(centerParts[0]);
  final lng = double.tryParse(centerParts[1]);
  final radiusKm = double.tryParse(parts[1]);
  if (lat == null || lng == null || radiusKm == null) return null;
  if (radiusKm < 0) return null;
  return WinterAlertCircle(
    center: GeoPoint(latitude: lat, longitude: lng),
    radiusKm: radiusKm,
  );
}

/// Thrown when `api.weather.gov` returns a payload whose GeoJSON shape
/// does not match this adapter's smallest-slice expectations.
///
/// Indicates one of:
/// - top-level `type` is not `"FeatureCollection"`;
/// - `features` is missing or not a list;
/// - a feature is missing the required `properties.event` field.
///
/// Consumers should treat this as transient (retry next poll) unless it
/// recurs across multiple consecutive calls, which suggests an
/// upstream schema change worth surfacing for a wrapper update.
class NoaaNwsParseException implements Exception {
  /// Human-readable description of the schema mismatch.
  final String message;

  const NoaaNwsParseException(this.message);

  @override
  String toString() => 'NoaaNwsParseException: $message';
}

String _readString(Map<String, dynamic> m, String key) {
  final v = m[key];
  return v is String ? v : '';
}

DateTime? _readDateTime(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}

AlertSeverity _parseSeverity(Object? v) {
  if (v is! String) return AlertSeverity.unknown;
  switch (v) {
    case 'Minor':
      return AlertSeverity.minor;
    case 'Moderate':
      return AlertSeverity.moderate;
    case 'Severe':
      return AlertSeverity.severe;
    case 'Extreme':
      return AlertSeverity.extreme;
    default:
      return AlertSeverity.unknown;
  }
}

AlertCertainty _parseCertainty(Object? v) {
  if (v is! String) return AlertCertainty.unknown;
  switch (v) {
    case 'Unlikely':
      return AlertCertainty.unlikely;
    case 'Possible':
      return AlertCertainty.possible;
    case 'Likely':
      return AlertCertainty.likely;
    case 'Observed':
      return AlertCertainty.observed;
    default:
      return AlertCertainty.unknown;
  }
}

AlertUrgency _parseUrgency(Object? v) {
  if (v is! String) return AlertUrgency.unknown;
  switch (v) {
    case 'Past':
      return AlertUrgency.past;
    case 'Future':
      return AlertUrgency.future;
    case 'Expected':
      return AlertUrgency.expected;
    case 'Immediate':
      return AlertUrgency.immediate;
    default:
      return AlertUrgency.unknown;
  }
}

AlertMessageType _parseMessageType(Object? v) {
  if (v is! String) return AlertMessageType.unknown;
  switch (v) {
    case 'Alert':
      return AlertMessageType.alert;
    case 'Update':
      return AlertMessageType.update;
    case 'Cancel':
      return AlertMessageType.cancel;
    default:
      return AlertMessageType.unknown;
  }
}

AlertStatus _parseStatus(Object? v) {
  if (v is! String) return AlertStatus.unknown;
  switch (v) {
    case 'Actual':
      return AlertStatus.actual;
    case 'Exercise':
      return AlertStatus.exercise;
    case 'System':
      return AlertStatus.system;
    case 'Test':
      return AlertStatus.test;
    case 'Draft':
      return AlertStatus.draft;
    default:
      return AlertStatus.unknown;
  }
}
