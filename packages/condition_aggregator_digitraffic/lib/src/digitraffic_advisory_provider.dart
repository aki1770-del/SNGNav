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
/// latitude ≈ 55 km, longitude varies with latitude. Conservative for
/// driver-relevant nearby-announcement surfacing.
const double kDefaultDigitrafficBoundingBoxHalfDegrees = 0.5;

/// Wall-clock budget for the HTTP fetch. A runaway publisher response
/// must not stall the driver-facing UI. The live response on 2026-05-24
/// was ~3.5 MB (1455 active announcements); 30 s is comfortable
/// headroom for slow-cellular conditions while preventing the integrator
/// HMI from stalling indefinitely.
const Duration _kFetchBudget = Duration(seconds: 30);

/// Hard cap on the response body in bytes. The 2026-05-24 live response
/// measured ~3.5 MB; 8 MB headroom prevents an unbounded growth in
/// active-announcement count from exhausting integrator memory.
const int _kMaxResponseBytes = 8 * 1024 * 1024;

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
/// map nor in [defaultDigitrafficCapMapping]. Conservative minor /
/// possible / unknown shape — the integrator should override on first
/// encounter of a new event class.
const DigitrafficCapMapping defaultDigitrafficFallbackMapping =
    DigitrafficCapMapping(
      severity: AdvisorySeverity.minor,
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

  final http.Client _client;
  final bool _ownsClient;

  /// Constructs an adapter that owns its own [http.Client].
  DigitrafficAdvisoryProvider({
    this.endpointUrl = kDefaultDigitrafficTrafficAnnouncementsUrl,
    this.boundingBoxHalfDegrees = kDefaultDigitrafficBoundingBoxHalfDegrees,
    Map<String, DigitrafficCapMapping>? capMapping,
    this.fallbackMapping = defaultDigitrafficFallbackMapping,
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
    if (response.bodyBytes.length > _kMaxResponseBytes) {
      throw DigitrafficHttpException(
        statusCode: response.statusCode,
        message:
            'Digitraffic response exceeded $_kMaxResponseBytes-byte '
            'cap (${response.bodyBytes.length} bytes received).',
      );
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
  final minLng = centerLongitude - halfDegrees;
  final maxLng = centerLongitude + halfDegrees;
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
