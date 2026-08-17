/// Mapper from OWM Road Risk alert payloads to the source-neutral
/// [Advisory] typed event used by the condition_aggregator umbrella.
///
/// Mapping discipline: caution-add-only — the `event_level` bucket
/// cut-points are chosen conservatively so the consumer warns earlier,
/// not later (see [OwmRoadRiskMapper.severityFromEventLevel]). The
/// mapping is a fixed lookup; there is no runtime rounding step.
/// Verbatim Article 17 (β) discipline applies to `event` and
/// `description` fields — the publisher's wording is preserved as the
/// `Advisory.eventClass` and `Advisory.description`.
library;

import 'package:condition_aggregator/condition_aggregator.dart';

import 'owm_road_risk_models.dart';

/// Static mapping primitives for OWM Road Risk → Advisory.
class OwmRoadRiskMapper {
  /// Maps the publisher's `event_level` integer to a CAP-class severity.
  /// Per the publisher's documentation the level is monotonic
  /// (higher = more severe); the bucket boundaries are chosen
  /// caution-add-only.
  static AdvisorySeverity severityFromEventLevel(int level) {
    if (level <= 0) return AdvisorySeverity.unknown;
    if (level == 1) return AdvisorySeverity.minor;
    if (level == 2) return AdvisorySeverity.moderate;
    if (level == 3) return AdvisorySeverity.severe;
    return AdvisorySeverity.extreme;
  }

  /// Builds an [Advisory] from one OWM Road Risk alert + the point
  /// the alert was returned for. The point lat/lon is folded into the
  /// `areaDescription` since the publisher's response does not include
  /// an area polygon for road-risk alerts.
  static Advisory toAdvisory({
    required OwmRoadRiskAlert alert,
    required double latitude,
    required double longitude,
  }) {
    return Advisory(
      source: AdvisorySource.other,
      eventClass: alert.event,
      severity: severityFromEventLevel(alert.eventLevel),
      certainty: AdvisoryCertainty.likely,
      urgency: AdvisoryUrgency.expected,
      areaDescription:
          'OpenWeatherMap Road Risk near ${latitude.toStringAsFixed(4)}, '
          '${longitude.toStringAsFixed(4)}. Issuer: ${alert.senderName}.',
      effective: null,
      expires: null,
      headline: alert.event.isEmpty ? '(no headline)' : alert.event,
      description: alert.description,
    );
  }

  /// Maps a list of alerts at a point to a list of Advisories. Empty
  /// input → empty output. Order is preserved.
  static List<Advisory> toAdvisoryList({
    required List<OwmRoadRiskAlert> alerts,
    required double latitude,
    required double longitude,
  }) {
    return [
      for (final a in alerts)
        toAdvisory(alert: a, latitude: latitude, longitude: longitude),
    ];
  }
}
