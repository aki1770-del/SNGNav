/// Domain models for the OpenWeatherMap Road Risk adapter.
///
/// Track / Waypoint match the request shape `POST /data/2.5/roadrisk`
/// expects (per https://openweathermap.org/api/road-risk). Alert mirrors
/// the response `alerts[]` shape — only the fields relevant to a
/// driver-facing Advisory consumer are surfaced; other fields (per-
/// waypoint road-surface temperature, dew point, snow accumulation,
/// ice-probability) are intentionally not modelled in this 0.1.0
/// smallest-slice. Adding them is back-compat additive and queued
/// for a future minor when an integrator surface needs them.
library;

import 'package:equatable/equatable.dart';

/// One waypoint on a tracked route. The publisher requires `lat`,
/// `lon`, and a Unix timestamp `dt` per waypoint. SNGNav's
/// `AdvisoryProvider` interface is point-based, so the adapter
/// constructs a single-waypoint track per `fetchActiveAdvisoriesAtPoint`
/// call; multi-waypoint routes can be supplied directly to the lower-
/// level [OwmRoadRiskClient.fetchTrack] API for forward-route queries.
class OwmRoadRiskWaypoint extends Equatable {
  /// WGS84 latitude in decimal degrees.
  final double latitude;

  /// WGS84 longitude in decimal degrees.
  final double longitude;

  /// Unix epoch seconds (UTC). When the driver is expected to be at
  /// this waypoint. Past values are tolerated by the publisher but
  /// the road-risk forecast loses meaning more than a few hours into
  /// the past.
  final int unixTime;

  const OwmRoadRiskWaypoint({
    required this.latitude,
    required this.longitude,
    required this.unixTime,
  });

  /// JSON-encodable map matching the publisher's request shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'lat': latitude,
    'lon': longitude,
    'dt': unixTime,
  };

  @override
  List<Object?> get props => [latitude, longitude, unixTime];
}

/// One alert entry from the publisher's `alerts[]` response array.
///
/// Field naming follows the publisher's JSON keys (snake_case) mapped
/// to Dart conventions (camelCase) without changing semantics.
class OwmRoadRiskAlert extends Equatable {
  /// `alerts[].event` — publisher's native event-class identifier.
  /// Examples per the publisher's documentation: "Heavy snow",
  /// "Black ice", "Storm". Verbatim from the publisher.
  final String event;

  /// `alerts[].event_level` — publisher's hazardous-level integer.
  /// Higher = more severe per the publisher's scale. Mapped to
  /// CAP-class severity by [OwmRoadRiskMapper].
  final int eventLevel;

  /// `alerts[].sender_name` — national agency name that issued the
  /// alert (varies by region).
  final String senderName;

  /// `alerts[].description` — multi-paragraph description of the
  /// alert. Verbatim from the publisher; not transformed.
  final String description;

  const OwmRoadRiskAlert({
    required this.event,
    required this.eventLevel,
    required this.senderName,
    required this.description,
  });

  /// Parse one entry from `alerts[]`.
  ///
  /// **There is no such thing as a "safe sentinel".** This doc used to say the
  /// parser "defaults missing values to safe sentinels rather than throwing" —
  /// that sentence is the exact ideology the Measured-or-Absent contract exists
  /// to retire, and leaving it in a published package teaches the next author to
  /// fabricate. What the code ACTUALLY does, stated plainly:
  ///
  /// * a missing `event_level` is parsed as `0`, and `0` is mapped by
  ///   [OwmRoadRiskMapper] to [AdvisorySeverity.unknown] — **never** to a low
  ///   severity. An unstated severity is not a benign one.
  /// * the string fields fall back to `''`, and an empty `event` surfaces as
  ///   the headline `'(no headline)'` — i.e. "the publisher sent no headline",
  ///   which is what it means. It is NOT a claim about the road.
  ///
  /// Nothing here manufactures a measurement. The severity path is the one that
  /// can reach a driver, and it says `unknown` when the publisher did not say.
  factory OwmRoadRiskAlert.fromJson(Map<String, dynamic> json) {
    return OwmRoadRiskAlert(
      event: (json['event'] as String?) ?? '',
      eventLevel: (json['event_level'] as int?) ?? 0,
      senderName: (json['sender_name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [event, eventLevel, senderName, description];
}

/// Thrown when the publisher's response cannot be parsed as expected.
class OwmRoadRiskParseException implements Exception {
  /// Human-readable description of the parse failure.
  final String message;

  const OwmRoadRiskParseException(this.message);

  @override
  String toString() => 'OwmRoadRiskParseException: $message';
}

/// Thrown when the publisher's API responds with a 4xx/5xx HTTP status.
class OwmRoadRiskHttpException implements Exception {
  /// HTTP status code returned by the publisher.
  final int statusCode;

  /// Response body (truncated to 500 chars to keep error logs honest
  /// without flooding them).
  final String responseBody;

  const OwmRoadRiskHttpException({
    required this.statusCode,
    required this.responseBody,
  });

  @override
  String toString() =>
      'OwmRoadRiskHttpException(status: $statusCode): $responseBody';
}
