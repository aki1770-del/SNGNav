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

