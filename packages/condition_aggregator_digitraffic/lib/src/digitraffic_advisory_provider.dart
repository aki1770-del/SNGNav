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

const String _kDigitrafficTrafficAnnouncementsUrl =
    'https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements';

/// Default bounding-box half-width in WGS84 degrees applied around a
/// requested point when filtering Digitraffic features. ~0.5 degrees
/// latitude ≈ 55 km, longitude varies with latitude. Conservative for
/// driver-relevant nearby-announcement surfacing.
const double _kDefaultBoundingBoxHalfDegrees = 0.5;

/// Adapter implementing [AdvisoryProvider] against the Digitraffic
/// traffic-announcements feed.
class DigitrafficAdvisoryProvider implements AdvisoryProvider {
  final http.Client _client;
  final bool _ownsClient;
  final double _boundingBoxHalfDegrees;

  /// Constructs an adapter that owns its own [http.Client].
  DigitrafficAdvisoryProvider({
    double boundingBoxHalfDegrees = _kDefaultBoundingBoxHalfDegrees,
  }) : _client = http.Client(),
       _ownsClient = true,
       _boundingBoxHalfDegrees = boundingBoxHalfDegrees;

  /// Constructs an adapter against a caller-supplied [http.Client]
  /// (test injection).
  DigitrafficAdvisoryProvider.withClient(
    http.Client client, {
    double boundingBoxHalfDegrees = _kDefaultBoundingBoxHalfDegrees,
  }) : _client = client,
       _ownsClient = false,
       _boundingBoxHalfDegrees = boundingBoxHalfDegrees;

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
  /// point, mapping each to a source-neutral [Advisory] record.
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.get(
      Uri.parse(_kDigitrafficTrafficAnnouncementsUrl),
      headers: const {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
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

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(response.body);
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
        halfDegrees: _boundingBoxHalfDegrees,
      )) {
        continue;
      }
      final advisory = mapTrafficAnnouncementFeatureToAdvisory(feature);
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
/// Field-level mapping (v0.0.1):
/// - `source` ← `AdvisorySource.other` (placeholder; see barrel doc)
/// - `eventClass` ← `properties.trafficAnnouncementType` (publisher
///   verbatim, e.g. `accident report`, `preliminary accident report`)
/// - `severity`, `certainty`, `urgency` ← `unknown` (Digitraffic does
///   not expose CAP-class fields directly; heuristic mapping is a
///   v0.0.2 candidate)
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
///   if available; else Finnish
///
/// Visible at top level for direct-call testing.
Advisory? mapTrafficAnnouncementFeatureToAdvisory(
  Map<String, dynamic> feature,
) {
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
  final description = chosen?['additionalInformation']?.toString() ?? '';
  final areaDescription = _composeAreaDescription(chosen);

  DateTime? effective;
  DateTime? expires;
  final time = chosen?['timeAndDuration'];
  if (time is Map<String, dynamic>) {
    effective = _parseIsoOrNull(time['startTime']);
    expires = _parseIsoOrNull(time['endTime']);
  }

  return Advisory(
    source: AdvisorySource.other,
    eventClass: eventClass,
    severity: AdvisorySeverity.unknown,
    certainty: AdvisoryCertainty.unknown,
    urgency: AdvisoryUrgency.unknown,
    areaDescription: areaDescription,
    effective: effective,
    expires: expires,
    headline: headline,
    description: description,
  );
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

/// Raised when the Digitraffic HTTP fetch returns a non-200 status.
class DigitrafficHttpException implements Exception {
  /// HTTP status code observed on the failing response.
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
