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

  /// Norwegian Meteorological Institute (Meteorologisk institutt).
  /// Underwriter of the MET Norway forecast / weather-warning feeds
  /// (api.met.no). Data is licensed CC-BY-4.0 and requires attribution
  /// in any consumer surface; see [AdvisorySource.attributionString].
  metNorway,

  /// Other (placeholder; explicit adapter declaration recommended over
  /// catch-all). Retained so adapters in early scaffold can declare
  /// without locking the enum surface prematurely.
  other,
}

/// Source-attribution presentation utilities for [AdvisorySource].
///
/// Exposes a publisher-credit-line per source so consumer surfaces can
/// render attribution honestly per each publisher's license terms:
/// - NWS / NOAA: U.S. Federal public-domain; attribution is not
///   required by the publisher but the convention is to credit so the
///   driver knows the source.
/// - JMA: Japan Meteorological Agency; public-data class, credit
///   recommended.
/// - MET Norway: CC-BY-4.0; attribution is *required* by the license.
extension AdvisorySourceAttribution on AdvisorySource {
  /// Verifiable publisher-credit string for the source. Suitable for a
  /// driver-facing surface (e.g. *"Source: U.S. National Weather
  /// Service (NOAA)"*) or a machine-readable attribution log.
  ///
  /// The string format is stable: change requires a major version
  /// bump. Adapters and integrators MAY localize the credit line at
  /// presentation time; the canonical English form lives here.
  String get attributionString {
    switch (this) {
      case AdvisorySource.nwsUnitedStates:
        return 'Source: U.S. National Weather Service (NOAA). '
            'Public-domain data — api.weather.gov.';
      case AdvisorySource.jmaJapan:
        return 'Source: Japan Meteorological Agency (気象庁 / JMA). '
            'Public-data class — www.jma.go.jp.';
      case AdvisorySource.metNorway:
        return 'Source: Norwegian Meteorological Institute '
            '(Meteorologisk institutt / MET Norway). '
            'CC BY 4.0 — api.met.no.';
      case AdvisorySource.other:
        return 'Source: Other — see adapter declaration.';
    }
  }
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

  /// Time elapsed since the publisher declared this advisory took
  /// effect, evaluated against [now]. Returns `null` when the
  /// publisher did not declare an [effective] timestamp — the
  /// advisory's freshness is then unknown at this layer; the
  /// integrator MUST treat unknown-freshness as a separate case from
  /// known-fresh and known-stale.
  ///
  /// Negative values are clamped to [Duration.zero] for the
  /// (uncommon) case where the publisher's [effective] is ahead of
  /// the consumer's clock — the advisory was published for the
  /// future. A future-effective advisory is fresh by definition; we
  /// do not let a clock-skew artefact present as "negative
  /// staleness".
  ///
  /// Driver-facing rationale: *"advisory carries its own freshness;
  /// the driver knows when the source last updated."* When a
  /// publisher (NWS / JMA / ...) has updated an advisory and a stale
  /// snapshot is still in flight, the integrator can compose
  /// [stalenessAt] with a per-event-class threshold to surface
  /// freshness honestly rather than rendering "current" against a
  /// last-fetched-an-hour-ago snapshot.
  Duration? stalenessAt(DateTime now) {
    final e = effective;
    if (e == null) return null;
    final delta = now.difference(e);
    if (delta < Duration.zero) return Duration.zero;
    return delta;
  }

  /// True iff the publisher-declared effective timestamp is non-null
  /// AND `now − effective` is at least [threshold]. False if
  /// [effective] is null (unknown freshness; not asserted to be
  /// stale at this layer).
  ///
  /// Composes with the integrator's per-event-class staleness
  /// budget, which is publisher- and event-class-specific — a
  /// `Winter Storm Warning` is typically updated at hourly cadence,
  /// while a `Freeze Warning` may carry a longer cadence. The
  /// package does not pick a default threshold; the integrator owns
  /// that policy.
  bool isStaleAt(DateTime now, Duration threshold) {
    final s = stalenessAt(now);
    if (s == null) return false;
    return s >= threshold;
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

  /// Serializes the advisory to a JSON-compatible map preserving
  /// publisher attribution + the full field set.
  ///
  /// Round-trip with [Advisory.fromJson] preserves equality. Used by
  /// integrators that persist advisories (telemetry-class observability,
  /// review queues, replay buffers) — the attribution channel survives
  /// the persistence boundary so the consumer downstream can credit
  /// the publisher correctly.
  ///
  /// Format:
  /// - `source` is the enum's name (e.g. `nwsUnitedStates`).
  /// - Enum-class fields (`severity`, `certainty`, `urgency`) are
  ///   serialized as their `.name`.
  /// - Nullable timestamps are serialized as ISO-8601 strings or null.
  /// - Free-form strings pass through verbatim.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'source': source.name,
      'eventClass': eventClass,
      'severity': severity.name,
      'certainty': certainty.name,
      'urgency': urgency.name,
      'areaDescription': areaDescription,
      'effective': effective?.toIso8601String(),
      'expires': expires?.toIso8601String(),
      'headline': headline,
      'description': description,
    };
  }

  /// Reconstructs an [Advisory] from a JSON-compatible map produced by
  /// [Advisory.toJson] (or any equivalent shape).
  ///
  /// Throws [AdvisoryDeserializationException] on missing / wrongly-typed
  /// required fields. Unknown enum names map to the corresponding
  /// `unknown` / `other` variant for forward-compat.
  static Advisory fromJson(Map<String, dynamic> json) {
    final eventClass = json['eventClass'];
    if (eventClass is! String) {
      throw const AdvisoryDeserializationException(
        "JSON 'eventClass' missing or not a String",
      );
    }
    final areaDescription = json['areaDescription'];
    if (areaDescription is! String) {
      throw const AdvisoryDeserializationException(
        "JSON 'areaDescription' missing or not a String",
      );
    }
    final headline = json['headline'];
    if (headline is! String) {
      throw const AdvisoryDeserializationException(
        "JSON 'headline' missing or not a String",
      );
    }
    final description = json['description'];
    if (description is! String) {
      throw const AdvisoryDeserializationException(
        "JSON 'description' missing or not a String",
      );
    }
    return Advisory(
      source: _sourceFromName(json['source']),
      eventClass: eventClass,
      severity: _severityFromName(json['severity']),
      certainty: _certaintyFromName(json['certainty']),
      urgency: _urgencyFromName(json['urgency']),
      areaDescription: areaDescription,
      effective: _parseIso8601(json['effective']),
      expires: _parseIso8601(json['expires']),
      headline: headline,
      description: description,
    );
  }
}

/// Thrown when [Advisory.fromJson] is asked to reconstruct an advisory
/// from a payload whose shape does not match the contract (missing
/// required field, wrong type at a required field). Forward-compat
/// fields (unknown enum names) do NOT throw — they map to `unknown` /
/// `other`.
class AdvisoryDeserializationException implements Exception {
  /// Human-readable description of the contract violation.
  final String message;

  const AdvisoryDeserializationException(this.message);

  @override
  String toString() => 'AdvisoryDeserializationException: $message';
}

AdvisorySource _sourceFromName(Object? raw) {
  if (raw is! String) return AdvisorySource.other;
  for (final v in AdvisorySource.values) {
    if (v.name == raw) return v;
  }
  return AdvisorySource.other;
}

AdvisorySeverity _severityFromName(Object? raw) {
  if (raw is! String) return AdvisorySeverity.unknown;
  for (final v in AdvisorySeverity.values) {
    if (v.name == raw) return v;
  }
  return AdvisorySeverity.unknown;
}

AdvisoryCertainty _certaintyFromName(Object? raw) {
  if (raw is! String) return AdvisoryCertainty.unknown;
  for (final v in AdvisoryCertainty.values) {
    if (v.name == raw) return v;
  }
  return AdvisoryCertainty.unknown;
}

AdvisoryUrgency _urgencyFromName(Object? raw) {
  if (raw is! String) return AdvisoryUrgency.unknown;
  for (final v in AdvisoryUrgency.values) {
    if (v.name == raw) return v;
  }
  return AdvisoryUrgency.unknown;
}

DateTime? _parseIso8601(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
