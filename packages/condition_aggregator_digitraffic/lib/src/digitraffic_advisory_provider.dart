/// DigitrafficAdvisoryProvider — `AdvisoryProvider` adapter for the
/// Fintraffic Digitraffic traffic-announcements feed.
///
/// Fetches `https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`
/// (open endpoint per Digitraffic swagger v3 `security: []` 2026-05-24
/// verification) and maps each GeoJSON feature to a source-neutral
/// `Advisory` typed event. Pure Dart; only `http` + `condition_aggregator`
/// runtime dependencies.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:http/http.dart' as http;

/// Default Digitraffic traffic-announcements endpoint — the public v2
/// product returning GeoJSON FeatureCollection of active announcements
/// across Finland.
const String kDefaultDigitrafficTrafficAnnouncementsUrl =
    'https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements';

/// Default bounding-box half-width in WGS84 degrees applied around a
/// requested point when filtering Digitraffic features. ~0.5 degrees
/// latitude ≈ 55 km.
///
/// This is the LATITUDE half-width. The longitude half-width is derived
/// from it by [_longitudeHalfDegrees] so the box is the same width in
/// kilometres on both axes. Applying this constant symmetrically was a
/// defect through 0.0.7: Digitraffic serves Finland only (~60°N–70°N),
/// where a degree of longitude is 34–50% of a degree of latitude, so the
/// east–west box was a third to a half of its documented width and
/// hazard announcements beside the driver were silently dropped.
const double kDefaultDigitrafficBoundingBoxHalfDegrees = 0.5;

/// Wall-clock budget for the HTTP fetch. A runaway publisher response
/// must not stall the driver-facing UI. The live response on 2026-05-24
/// was ~3.5 MB (1455 active announcements); 30 s is comfortable
/// headroom for slow-cellular conditions while preventing the integrator
/// HMI from stalling indefinitely.
const Duration _kFetchBudget = Duration(seconds: 30);

/// Soft cap on the response body in bytes used only to emit a
/// diagnostic warning — NOT to reject the response.
///
/// History: the v0.0.2/v0.0.3 adapter applied a *hard* 8 MB cap that
/// THREW [DigitrafficHttpException] on any larger body. The live
/// all-Finland `/v2/traffic-announcements` payload is not stable — it
/// tracks the active-announcement count and the size of attached area
/// geometries, and was measured well above 8 MB (~16.4 MB) during a
/// peak. A hard throw on a perfectly valid HTTP 200 broke the adapter
/// for every edge developer fetching live Finnish road data at those
/// times — not just our demo.
///
/// The v2 traffic-announcements endpoint exposes NO server-side
/// area / bbox / situationType query parameters (Digitraffic OpenAPI
/// spec + live 400 responses verified 2026-05-30), so the payload
/// cannot be narrowed at the server; the adapter must accept the
/// all-Finland body and filter client-side. The adapter therefore
/// degrades gracefully: when a body exceeds this threshold it surfaces
/// a diagnostic via [DigitrafficAdvisoryProvider.onLargeResponse] and
/// parses anyway rather than discarding a valid 200. 32 MB is well
/// above observed volumes, so the warning fires only on genuinely
/// anomalous growth — and even then the response is still parsed,
/// never thrown away.
const int _kSoftResponseWarnBytes = 32 * 1024 * 1024;

/// CAP-class mapping derived from one `trafficAnnouncementType` value
/// to severity / certainty / urgency tuple — integrator-overridable at
/// adapter construction time per the parent
/// `condition_aggregator` integrator-overridable threshold precedent.
///
/// Used by [DigitrafficAdvisoryProvider] and the top-level
/// [mapTrafficAnnouncementFeatureToAdvisory] mapping function. The
/// adapter ships a [defaultDigitrafficCapMapping] sourced from the
/// 2026-05-24 live API genchi-genbutsu (5 `trafficAnnouncementType`
/// values observed across 1455 active announcements). Integrators with
/// region-specific risk profiles SHOULD override per-event-class —
/// e.g., a rural-Finland integrator may rank `general` higher than the
/// conservative default `minor`.
class DigitrafficCapMapping {
  /// CAP-class severity for this event class.
  final AdvisorySeverity severity;

  /// CAP-class certainty for this event class.
  final AdvisoryCertainty certainty;

  /// CAP-class urgency for this event class.
  final AdvisoryUrgency urgency;

  const DigitrafficCapMapping({
    required this.severity,
    required this.certainty,
    required this.urgency,
  });
}

/// Default CAP-class mapping from `trafficAnnouncementType` to
/// (severity, certainty, urgency) — sourced from the 2026-05-24 live
/// Digitraffic API genchi-genbutsu (`/v2/traffic-announcements` at
/// 08:53 UTC; 1455 active features; 5 distinct event-class values:
/// `accident report` (711), `general` (442),
/// `preliminary accident report` (158), `ended` (143),
/// `retracted` (1)).
///
/// Mapping shape (all values appear in the live API; the map is
/// exhaustive against 2026-05-24 ground-truth; unknown future values
/// fall through to a conservative default per
/// [mapTrafficAnnouncementFeatureToAdvisory]):
///
/// - `accident report` → severe / observed / immediate
///   (publisher has observed an accident; driver-actionable now)
/// - `preliminary accident report` → moderate / likely / expected
///   (publisher has unconfirmed indication; less certain than
///   `accident report`)
/// - `general` → minor / possible / expected
///   (catch-all category in the Digitraffic vocabulary; could be road
///   works, traffic restriction, event traffic; conservative minor
///   default invites integrator override per region)
/// - `ended` → minor / observed / past
///   (the situation has ended; surfacing supports stale-cache UI
///   reconciliation but is not driver-actionable as a current event)
/// - `retracted` → minor / unlikely / past
///   (the publisher retracted a prior announcement; informational
///   only)
///
/// Carry-forward (v0.0.3 candidate): symbol-class refinement via
/// `properties.announcements[].features[]` (which carry granular tags
/// like `wildlife`, `road works`, `weather`) for additional CAP-class
/// derivation under each `trafficAnnouncementType`.
const Map<String, DigitrafficCapMapping> defaultDigitrafficCapMapping =
    <String, DigitrafficCapMapping>{
      'accident report': DigitrafficCapMapping(
        severity: AdvisorySeverity.severe,
        certainty: AdvisoryCertainty.observed,
        urgency: AdvisoryUrgency.immediate,
      ),
      'preliminary accident report': DigitrafficCapMapping(
        severity: AdvisorySeverity.moderate,
        certainty: AdvisoryCertainty.likely,
        urgency: AdvisoryUrgency.expected,
      ),
      'general': DigitrafficCapMapping(
        severity: AdvisorySeverity.minor,
        certainty: AdvisoryCertainty.possible,
        urgency: AdvisoryUrgency.expected,
      ),
      'ended': DigitrafficCapMapping(
        severity: AdvisorySeverity.minor,
        certainty: AdvisoryCertainty.observed,
        urgency: AdvisoryUrgency.past,
      ),
      'retracted': DigitrafficCapMapping(
        severity: AdvisorySeverity.minor,
        certainty: AdvisoryCertainty.unlikely,
        urgency: AdvisoryUrgency.past,
      ),
    };

/// Default fallback CAP mapping applied when an observed
/// `trafficAnnouncementType` is not present in the provided override
/// map nor in [defaultDigitrafficCapMapping].
///
/// The severity is [AdvisorySeverity.unknown] — **not** `minor`.
///
/// Up to 0.0.6 it was `minor`, described as "conservative". Minor is not
/// conservative for an event class we cannot classify at all: it is an
/// ASSERTED benign severity for an announcement whose severity we do not know.
/// If Fintraffic adds a new severe-class announcement type tomorrow, every
/// driver on this adapter would be told "minor" until somebody noticed.
///
/// `unknown` is the honest value, it already exists on the enum, and it is used
/// correctly elsewhere in this catalog (`owm_road_risk_mapper.dart`: an
/// `event_level <= 0` maps to `AdvisorySeverity.unknown`). The integrator
/// override hook is unchanged — this is the value used until they exercise it.
const DigitrafficCapMapping defaultDigitrafficFallbackMapping =
    DigitrafficCapMapping(
      severity: AdvisorySeverity.unknown,
      certainty: AdvisoryCertainty.possible,
      urgency: AdvisoryUrgency.unknown,
    );

/// Adapter implementing [AdvisoryProvider] against the Digitraffic
/// traffic-announcements feed.
class DigitrafficAdvisoryProvider implements AdvisoryProvider {
  /// Endpoint URL. Default points at the public
  /// `/v2/traffic-announcements` product.
  final String endpointUrl;

  /// Bounding-box half-width in WGS84 degrees around the requested
  /// point used to filter the GeoJSON FeatureCollection. Integrator-
  /// overridable at construction time.
  final double boundingBoxHalfDegrees;

  /// CAP-class mapping by `trafficAnnouncementType`. Defaults to
  /// [defaultDigitrafficCapMapping]; integrators MAY pass an override
  /// (e.g. with rural-Finland-bias severities) at construction time.
  /// Values not present here AND not in
  /// [defaultDigitrafficCapMapping] fall through to
  /// [fallbackMapping].
  final Map<String, DigitrafficCapMapping> capMapping;

  /// Fallback CAP-class mapping applied when an observed
  /// `trafficAnnouncementType` is not present in [capMapping].
  /// Defaults to [defaultDigitrafficFallbackMapping].
  final DigitrafficCapMapping fallbackMapping;

  /// Optional diagnostic hook invoked when a response body exceeds
  /// [_kSoftResponseWarnBytes]. The adapter still parses and returns the
  /// (valid) body; this callback exists so an integrator can log /
  /// surface the anomaly. Defaults to null (no-op). Receives the
  /// observed body length in bytes.
  final void Function(int observedBytes)? onLargeResponse;

  final http.Client _client;
  final bool _ownsClient;

  /// Constructs an adapter that owns its own [http.Client].
  DigitrafficAdvisoryProvider({
    this.endpointUrl = kDefaultDigitrafficTrafficAnnouncementsUrl,
    this.boundingBoxHalfDegrees = kDefaultDigitrafficBoundingBoxHalfDegrees,
    Map<String, DigitrafficCapMapping>? capMapping,
    this.fallbackMapping = defaultDigitrafficFallbackMapping,
    this.onLargeResponse,
  }) : capMapping = capMapping ?? defaultDigitrafficCapMapping,
       _client = http.Client(),
       _ownsClient = true;

  /// Constructs an adapter against a caller-supplied [http.Client]
  /// (test injection). The adapter does not own the lifecycle of an
  /// injected client; the caller owns close().
  DigitrafficAdvisoryProvider.withClient(
    http.Client client, {
    this.endpointUrl = kDefaultDigitrafficTrafficAnnouncementsUrl,
    this.boundingBoxHalfDegrees = kDefaultDigitrafficBoundingBoxHalfDegrees,
    Map<String, DigitrafficCapMapping>? capMapping,
    this.fallbackMapping = defaultDigitrafficFallbackMapping,
    this.onLargeResponse,
  }) : capMapping = capMapping ?? defaultDigitrafficCapMapping,
       _client = client,
       _ownsClient = false;

  /// Names the publisher this adapter speaks for.
  ///
  /// Returns [AdvisorySource.other] as a placeholder until the
  /// `condition_aggregator` interface adds a Finnish member; see
  /// package barrel doc for the carry-forward.
  @override
  AdvisorySource get source => AdvisorySource.other;

  /// One-shot init. Digitraffic requires no auth handshake; init is a
  /// no-op for this adapter and never throws.
  @override
  Future<void> init() async {
    // Intentional no-op. Digitraffic publishes open data; no schema
    // negotiation, no auth handshake; configuration is fully
    // constructor-injected.
  }

  /// Fetches active traffic announcements from Digitraffic and filters
  /// to features that intersect a small bounding box around the given
  /// point, mapping each to a source-neutral [Advisory] record using
  /// the adapter's [capMapping] for CAP-class severity / certainty /
  /// urgency derivation.
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    // NOTE: the live /v2/traffic-announcements endpoint accepts NO query
    // parameters (server-side bbox / situationType narrowing is not
    // available on v2; verified against the Digitraffic OpenAPI spec and
    // live HTTP 400 responses on 2026-05-30). The full all-Finland
    // FeatureCollection is fetched and filtered client-side via
    // [_featureIntersectsBoundingBox].
    final response = await _client
        .get(
          Uri.parse(endpointUrl),
          headers: const {
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
          },
        )
        .timeout(
          _kFetchBudget,
          onTimeout: () {
            throw DigitrafficHttpException(
              statusCode: 0,
              message:
                  'Wall-clock budget ${_kFetchBudget.inSeconds}s '
                  'exhausted before Digitraffic response.',
            );
          },
        );
    if (response.statusCode != 200) {
      throw DigitrafficHttpException(
        statusCode: response.statusCode,
        message:
            'Digitraffic traffic-announcements fetch failed: '
            'HTTP ${response.statusCode}',
      );
    }
    // Graceful degradation: a large-but-valid body is NOT rejected. The
    // publisher payload has grown over time (3.5 MB → 16.4 MB) and a
    // hard throw on a valid HTTP 200 would break every consumer. We
    // surface a diagnostic via [onLargeResponse] and parse anyway.
    if (response.bodyBytes.length > _kSoftResponseWarnBytes) {
      onLargeResponse?.call(response.bodyBytes.length);
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const DigitrafficParseException(
          'Digitraffic response is not a JSON object',
        );
      }
      json = decoded;
    } on FormatException catch (e) {
      throw DigitrafficParseException(
        'Digitraffic response is not valid JSON: ${e.message}',
      );
    }

    final featuresRaw = json['features'];
    if (featuresRaw is! List) {
      throw const DigitrafficParseException(
        'Digitraffic response missing "features" array',
      );
    }

    final advisories = <Advisory>[];
    for (final feature in featuresRaw) {
      if (feature is! Map<String, dynamic>) continue;
      if (!_featureIntersectsBoundingBox(
        feature: feature,
        centerLatitude: latitude,
        centerLongitude: longitude,
        halfDegrees: boundingBoxHalfDegrees,
      )) {
        continue;
      }
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(
        feature,
        capMapping: capMapping,
        fallbackMapping: fallbackMapping,
      );
      if (advisory != null) advisories.add(advisory);
    }
    return List.unmodifiable(advisories);
  }

  /// Releases the underlying [http.Client] HTTP resources if this
  /// adapter constructed it; no-op if a caller-supplied client was
  /// injected via [DigitrafficAdvisoryProvider.withClient].
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Returns true if the GeoJSON feature's geometry is within
/// `halfDegrees` of the center point in either latitude or longitude.
/// Accepts Point, MultiPoint, LineString, and Polygon geometries by
/// testing every coordinate. Features without geometry are excluded.
bool _featureIntersectsBoundingBox({
  required Map<String, dynamic> feature,
  required double centerLatitude,
  required double centerLongitude,
  required double halfDegrees,
}) {
  final geometry = feature['geometry'];
  if (geometry is! Map<String, dynamic>) return false;
  final coords = geometry['coordinates'];
  if (coords == null) return false;
  final minLat = centerLatitude - halfDegrees;
  final maxLat = centerLatitude + halfDegrees;
  // Longitude degrees are shorter than latitude degrees away from the
  // equator; using halfDegrees on both axes narrowed the box to 34-50% of
  // its documented width across Finland. See _longitudeHalfDegrees.
  final lngHalfDegrees = _longitudeHalfDegrees(halfDegrees, centerLatitude);
  final minLng = centerLongitude - lngHalfDegrees;
  final maxLng = centerLongitude + lngHalfDegrees;
  return _anyCoordinateInBox(
    coords,
    minLat: minLat,
    maxLat: maxLat,
    minLng: minLng,
    maxLng: maxLng,
  );
}

bool _anyCoordinateInBox(
  Object? coords, {
  required double minLat,
  required double maxLat,
  required double minLng,
  required double maxLng,
}) {
  if (coords is List && coords.isNotEmpty) {
    final first = coords.first;
    if (first is num && coords.length >= 2) {
      // [lng, lat] (GeoJSON order).
      final lng = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
    }
    for (final c in coords) {
      if (_anyCoordinateInBox(
        c,
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
      )) {
        return true;
      }
    }
  }
  return false;
}

/// Maps one Digitraffic traffic-announcement GeoJSON feature to a
/// source-neutral [Advisory], or returns null if the feature lacks
/// minimum required fields.
///
/// Field-level mapping (v0.0.2):
/// - `source` ← `AdvisorySource.other` (placeholder; see barrel doc)
/// - `eventClass` ← `properties.trafficAnnouncementType` (publisher
///   verbatim, e.g. `accident report`, `preliminary accident report`,
///   `general`, `ended`, `retracted` — the 5 values observed in the
///   2026-05-24 live API genchi-genbutsu)
/// - `severity`, `certainty`, `urgency` ← derived via [capMapping]
///   lookup on `trafficAnnouncementType`; falls through to
///   [fallbackMapping] for unobserved future event-class values
///   (defaults to [defaultDigitrafficCapMapping] +
///   [defaultDigitrafficFallbackMapping])
/// - `areaDescription` ← English-localized `announcements[].location` +
///   `locationDetails` text if present; otherwise the Finnish
///   primary-language entry. Verbatim from the publisher.
/// - `effective` ← `announcements[].timeAndDuration.startTime`
///   (nullable; ISO 8601)
/// - `expires` ← `announcements[].timeAndDuration.endTime`
///   (nullable; ISO 8601)
/// - `headline` ← English `announcements[].title` if available; else
///   Finnish title
/// - `description` ← English `announcements[].additionalInformation`
///   if available; else Finnish; with the Fintraffic CC-BY-4.0
///   attribution line appended verbatim
///
/// Visible at top level for direct-call testing.
Advisory? mapTrafficAnnouncementFeatureToAdvisory(
  Map<String, dynamic> feature, {
  Map<String, DigitrafficCapMapping> capMapping = defaultDigitrafficCapMapping,
  DigitrafficCapMapping fallbackMapping = defaultDigitrafficFallbackMapping,
}) {
  final props = feature['properties'];
  if (props is! Map<String, dynamic>) return null;
  final eventClass = props['trafficAnnouncementType'];
  if (eventClass is! String || eventClass.isEmpty) return null;

  final announcements = props['announcements'];
  Map<String, dynamic>? englishAnnouncement;
  Map<String, dynamic>? primaryAnnouncement;
  if (announcements is List) {
    for (final a in announcements) {
      if (a is! Map<String, dynamic>) continue;
      primaryAnnouncement ??= a;
      if (a['language'] == 'en') {
        englishAnnouncement = a;
        break;
      }
    }
  }
  final chosen = englishAnnouncement ?? primaryAnnouncement;

  final headline = chosen?['title']?.toString() ?? '';
  final baseDescription = chosen?['additionalInformation']?.toString() ?? '';
  final areaDescription = _composeAreaDescription(chosen);

  DateTime? effective;
  DateTime? expires;
  final time = chosen?['timeAndDuration'];
  if (time is Map<String, dynamic>) {
    effective = _parseIsoOrNull(time['startTime']);
    expires = _parseIsoOrNull(time['endTime']);
  }

  // CAP-class derivation per integrator-overridable mapping; fall
  // through to fallback for unobserved future event-class values.
  final mapping = capMapping[eventClass] ?? fallbackMapping;

  final description = _composeDescription(baseDescription: baseDescription);

  return Advisory(
    source: AdvisorySource.other,
    eventClass: eventClass,
    severity: mapping.severity,
    certainty: mapping.certainty,
    urgency: mapping.urgency,
    areaDescription: areaDescription,
    effective: effective,
    expires: expires,
    headline: headline,
    description: description,
  );
}

/// Fintraffic-required attribution line per Fintraffic Terms of
/// Service (`https://www.digitraffic.fi/en/terms-of-service/`,
/// verified 2026-05-24): *"Source: Fintraffic / digitraffic.fi,
/// license CC 4.0 BY"*. Surfaced verbatim in every emitted advisory's
/// description field so the credit reaches the driver-facing HMI surface
/// per CC-BY-4.0 §3(a)(1)(a)-(c) attribution conditions.
const String kDigitrafficAttributionString =
    'Source: Fintraffic / digitraffic.fi, license CC 4.0 BY.';

String _composeDescription({required String baseDescription}) {
  if (baseDescription.isEmpty) return kDigitrafficAttributionString;
  return '$baseDescription. $kDigitrafficAttributionString';
}

String _composeAreaDescription(Map<String, dynamic>? announcement) {
  if (announcement == null) return '';
  final parts = <String>[];
  final location = announcement['location'];
  if (location is Map<String, dynamic>) {
    final description = location['description'];
    if (description is String && description.isNotEmpty) {
      parts.add(description);
    }
  }
  final locationDetails = announcement['locationDetails'];
  if (locationDetails is Map<String, dynamic>) {
    final road = locationDetails['roadAddressLocation'];
    if (road is Map<String, dynamic>) {
      final primaryPoint = road['primaryPoint'];
      if (primaryPoint is Map<String, dynamic>) {
        final roadName = primaryPoint['roadName'];
        if (roadName is String && roadName.isNotEmpty) parts.add(roadName);
      }
    }
  }
  return parts.join(' — ');
}

DateTime? _parseIsoOrNull(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    return null;
  }
}

/// Raised when the Digitraffic HTTP fetch returns a non-200 status or
/// exceeds a documented byte / wall-clock cap.
class DigitrafficHttpException implements Exception {
  /// HTTP status code observed on the failing response. Set to 0 for
  /// pre-response failures (wall-clock timeout, transport error).
  final int statusCode;

  /// Human-readable description of the failure.
  final String message;

  const DigitrafficHttpException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() =>
      'DigitrafficHttpException(statusCode: $statusCode): $message';
}

/// Raised when the Digitraffic response body cannot be parsed as the
/// expected GeoJSON FeatureCollection JSON.
class DigitrafficParseException implements Exception {
  /// Human-readable description of the contract violation.
  final String message;

  const DigitrafficParseException(this.message);

  @override
  String toString() => 'DigitrafficParseException: $message';
}

/// Longitude half-width in degrees that spans the same ground distance as
/// [halfDegrees] of latitude at [latitude].
///
/// A degree of longitude shrinks as `cos(latitude)`, so a box that uses the
/// same degree count on both axes is narrower east–west everywhere except the
/// equator. Digitraffic never operates near the equator. Mirrors the
/// pole-guarded pattern already used in `offline_tiles`
/// (`offline_tile_manager.dart:243-251`).
double _longitudeHalfDegrees(double halfDegrees, double latitude) {
  final cosLat = math.cos(latitude * math.pi / 180).abs();
  // Pole guard: cos -> 0 at the poles would widen the box without bound.
  if (cosLat < 0.001) return 180.0;
  return math.min(180.0, halfDegrees / cosLat);
}
