/// Advisory — source-neutral typed advisory event.
///
/// One advisory record produced by an [AdvisoryProvider] adapter from a
/// publisher source (NWS / JMA / JARTIC / NEXCO / prefectural / etc.).
/// Fields are normalized across sources at the interface boundary so the
/// integrator (downstream of this package) consumes one shape regardless
/// of which source published the underlying advisory.
///
/// Severity / certainty / urgency follow CAP-class semantics — the same
/// vocabulary CAP-class adapters (NWS) use natively, and that JMA / other
/// non-CAP-class adapters map to from their native classification.
library;

import 'package:equatable/equatable.dart';

/// Source attribution for an [Advisory] — names the publisher whose
/// authority underwrites the record.
///
/// Severity-not-profile invariant (per AAA bylaws + D4): all sources are
/// represented at the interface; the integrator does not pre-filter by
/// region or driver-profile at this layer. Per-region adapter selection
/// happens at composition time in the consuming app.
enum AdvisorySource {
  /// United States National Weather Service (NOAA).
  /// Underwriter of the public-domain CAP-class winter-alert feed at
  /// `api.weather.gov`.
  nwsUnitedStates,

  /// Japan Meteorological Agency (気象庁).
  /// Underwriter of the JMA disaster-info XML feed (jmaxml).
  jmaJapan,

  /// Other (placeholder; explicit adapter declaration recommended over
  /// catch-all). Retained so adapters in early scaffold can declare
  /// without locking the enum surface prematurely.
  other,
}

/// CAP-class severity classification.
///
/// Mirrored from NWS GeoJSON `severity` field; non-CAP sources (e.g. JMA)
/// map their native classification to this scale at adapter boundary.
enum AdvisorySeverity { unknown, minor, moderate, severe, extreme }

/// CAP-class certainty classification.
enum AdvisoryCertainty { unknown, unlikely, possible, likely, observed }

/// CAP-class urgency classification.
enum AdvisoryUrgency { unknown, past, future, expected, immediate }

/// One typed advisory event.
///
/// All required fields non-null (per construction); optional timestamps
/// nullable since publisher schemas legitimately omit them on some
/// advisory classes.
///
/// Equatable for stream de-duplication when consumed via a polling pipe.
class Advisory extends Equatable {
  /// Publisher attribution.
  final AdvisorySource source;

  /// Publisher's native event-class identifier, verbatim. Examples:
  /// NWS — `Winter Storm Warning`, `Blizzard Warning`.
  /// JMA — report-family code `VPWW54`, `VPCJ51`.
  /// The interface preserves the publisher's vocabulary; downstream
  /// renderers MAY localize but the publisher string is the canonical
  /// substrate per Article 17 (β) verbatim-relay discipline.
  final String eventClass;

  /// Normalized severity per CAP scale.
  final AdvisorySeverity severity;

  /// Normalized certainty per CAP scale.
  final AdvisoryCertainty certainty;

  /// Normalized urgency per CAP scale.
  final AdvisoryUrgency urgency;

  /// Free-form area description from the publisher (e.g. county list,
  /// 都道府県 list). Verbatim from the publisher; not transformed.
  final String areaDescription;

  /// When the advisory takes effect. Nullable per CAP spec.
  final DateTime? effective;

  /// When the advisory expires. Nullable per CAP spec.
  final DateTime? expires;

  /// Short human-readable headline from the publisher.
  final String headline;

  /// Multi-paragraph description from the publisher.
  final String description;

  const Advisory({
    required this.source,
    required this.eventClass,
    required this.severity,
    required this.certainty,
    required this.urgency,
    required this.areaDescription,
    required this.effective,
    required this.expires,
    required this.headline,
    required this.description,
  });

  /// True if severity is severe or extreme — driver-actionable signal.
  bool get isHighImpact =>
      severity == AdvisorySeverity.severe ||
      severity == AdvisorySeverity.extreme;

  /// True if [expires] is non-null and in the past relative to [now].
  /// `false` if [expires] is null (publisher did not declare expiry).
  bool isExpiredAt(DateTime now) {
    final e = expires;
    if (e == null) return false;
    return e.isBefore(now);
  }

  @override
  List<Object?> get props => <Object?>[
        source,
        eventClass,
        severity,
        certainty,
        urgency,
        areaDescription,
        effective,
        expires,
        headline,
        description,
      ];

  @override
  String toString() =>
      'Advisory(source: ${source.name}, eventClass: $eventClass, '
      'severity: ${severity.name}, area: $areaDescription, '
      'effective: $effective, expires: $expires)';
}
