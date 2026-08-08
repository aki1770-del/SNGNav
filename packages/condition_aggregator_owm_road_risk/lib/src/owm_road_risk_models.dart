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
  /// Higher = more severe per the publisher's scale.
  ///
  /// **Do not threshold on this field.** It is non-null for source
  /// compatibility, and it reads `0` in two situations that are not the same
  /// fact: the publisher stated level `0`, and the publisher stated no level
  /// at all. `0` is the bottom of the scale, so a comparison such as
  /// `eventLevel >= 2` silently treats an unstated level as a mild one — an
  /// unmeasured field buying a downgrade.
  ///
  /// Use [reportedEventLevel] instead. It is `null` when the publisher did not
  /// state a level, and `null` is *off* the scale rather than at the benign end
  /// of it, so the analyzer stops a comparison rather than letting one silently
  /// under-warn.
  final int eventLevel;

  /// Whether the publisher's record actually carried a usable `event_level`.
  ///
  /// `false` means the field was absent, or was present in a form this adapter
  /// will not coerce into a level (see [OwmRoadRiskAlert.fromJson]). The rest
  /// of the alert — the event name, the issuer, the description — is still
  /// real and is preserved; only the level is unknown.
  ///
  /// Defaults to `true` so that alerts constructed directly (rather than
  /// parsed) keep their pre-0.1.5 meaning: the caller supplied a level, so the
  /// level was stated.
  final bool eventLevelWasReported;

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
    this.eventLevelWasReported = true,
  });

  /// The level the publisher actually stated, or `null` when it stated none.
  ///
  /// This is the field to compare against. `null` is not a low level; it is
  /// the absence of one, and it maps to [AdvisorySeverity.unknown] rather than
  /// to any rung of the severity scale.
  int? get reportedEventLevel => eventLevelWasReported ? eventLevel : null;

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
  ///
  /// Since 0.1.5 the absence is also *carried*, not merely mapped: an absent or
  /// uncoercible `event_level` sets [eventLevelWasReported] to `false`, so
  /// [reportedEventLevel] is `null` and a caller reading the alert directly can
  /// see that no level was stated. Before 0.1.5 an absent level and a stated
  /// level `0` produced equal values of this class, and the distinction was
  /// only recoverable at the [Advisory] layer.
  ///
  /// `event_level` is accepted as a JSON integer, or as a JSON number with no
  /// fractional part (`3.0`), which some publishers emit and which converts
  /// without loss. Any other shape — a string, a fractional number, a
  /// non-finite number, an object — is treated as *not stated* rather than
  /// coerced into a level or thrown past the caller. Before 0.1.5 such a value
  /// escaped as a `TypeError`, which is an `Error` rather than an `Exception`
  /// and so was not caught by callers guarding the adapter contract's declared
  /// exception types.
  factory OwmRoadRiskAlert.fromJson(Map<String, dynamic> json) {
    final level = _levelFrom(json['event_level']);
    return OwmRoadRiskAlert(
      event: (json['event'] as String?) ?? '',
      eventLevel: level ?? 0,
      eventLevelWasReported: level != null,
      senderName: (json['sender_name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }

  /// Reads a publisher `event_level` without inventing one.
  ///
  /// Returns `null` for every value this adapter will not vouch for, which is
  /// the honest outcome: we did not learn the level. It never rounds, never
  /// truncates, and never substitutes a default.
  static int? _levelFrom(Object? raw) {
    if (raw is int) return raw;
    if (raw is double) {
      // Whole-valued doubles are the same integer, exactly. Fractional or
      // non-finite values are not a level on this publisher's integer scale,
      // and rounding one would be a measurement we did not take.
      if (raw.isFinite && raw == raw.roundToDouble()) return raw.toInt();
      return null;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    event,
    eventLevel,
    eventLevelWasReported,
    senderName,
    description,
  ];
}

/// The outcome of one read of the publisher's road-risk endpoint: what this
/// adapter could read, together with what it could not.
///
/// A bare `List<OwmRoadRiskAlert>` cannot express a partial read. An empty list
/// means "the publisher answered and nothing is active" per the
/// `AdvisoryProvider` contract, so returning one after discarding entries this
/// adapter failed to parse would report a measurement that was never taken.
/// This type keeps the two apart.
class OwmRoadRiskRead {
  /// The alerts that were read successfully. Order follows the publisher's.
  final List<OwmRoadRiskAlert> alerts;

  /// How many entries in the publisher's response could not be read at all.
  ///
  /// Counts whole entries that were discarded — a track item that was not an
  /// object, an `alerts` value that was not an array, an alert entry that was
  /// not an object. An alert whose *level* alone was missing is not counted
  /// here: that alert was read, and its absent level is carried on the alert
  /// itself via [OwmRoadRiskAlert.reportedEventLevel].
  final int unreadableEntries;

  /// One short, human-readable cause per discarded entry, in encounter order.
  /// Intended for logs and for the incomplete-read notice; not a stable API
  /// for programmatic matching.
  final List<String> unreadableCauses;

  const OwmRoadRiskRead({
    required this.alerts,
    required this.unreadableEntries,
    required this.unreadableCauses,
  });

  /// True when every entry in the publisher's response was read.
  ///
  /// When this is `false`, [alerts] is a floor and not a complete picture:
  /// something was in the response that this adapter could not interpret, and
  /// it may have been a hazard.
  bool get isComplete => unreadableEntries == 0;
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
