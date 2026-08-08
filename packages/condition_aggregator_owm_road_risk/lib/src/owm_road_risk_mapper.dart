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

/// `Advisory.eventClass` identity for the synthetic **incomplete-read** notice
/// that [OwmRoadRiskProvider.fetchActiveAdvisoriesAtPoint] appends when part of
/// the publisher's response could not be read.
///
/// This is not a road-risk event. It is a completeness notice, and it is
/// deliberately shaped so it can never be mistaken for one: the publisher's own
/// `event` values are human phrases such as "Black ice" or "Heavy snow", while
/// this identity is a slash-namespaced token no publisher emits. Consumers that
/// want to filter it out, or render it differently from a hazard, match
/// `Advisory.eventClass == kOwmRoadRiskIncompleteReadEventClass`.
const String kOwmRoadRiskIncompleteReadEventClass =
    'owm-road-risk/incomplete-read';

/// Static mapping primitives for OWM Road Risk → Advisory.
class OwmRoadRiskMapper {
  /// Maps the publisher's `event_level` integer to a CAP-class severity.
  /// Per the publisher's documentation the level is monotonic
  /// (higher = more severe); the bucket boundaries are chosen
  /// caution-add-only.
  ///
  /// This overload takes a non-null level and therefore cannot distinguish a
  /// stated level `0` from an unstated one; it maps `<= 0` to
  /// [AdvisorySeverity.unknown], which is correct for both. Prefer
  /// [severityFromAlert], which reads the absence from the alert itself.
  static AdvisorySeverity severityFromEventLevel(int level) {
    if (level <= 0) return AdvisorySeverity.unknown;
    if (level == 1) return AdvisorySeverity.minor;
    if (level == 2) return AdvisorySeverity.moderate;
    if (level == 3) return AdvisorySeverity.severe;
    return AdvisorySeverity.extreme;
  }

  /// Severity for one alert, reading the publisher's stated level when there is
  /// one and [AdvisorySeverity.unknown] when there is not.
  ///
  /// An unstated level does not fall to the bottom of the scale here. It leaves
  /// the scale: `unknown` is a distinct member, and the umbrella's
  /// `Advisory.isHighImpact` tests severity by member equality rather than by
  /// ordinal, so an unknown severity is neither ranked below `minor` nor
  /// promoted above it.
  static AdvisorySeverity severityFromAlert(OwmRoadRiskAlert alert) {
    final level = alert.reportedEventLevel;
    if (level == null) return AdvisorySeverity.unknown;
    return severityFromEventLevel(level);
  }

  /// Builds the clearly-marked, low-severity **incomplete-read** notice for a
  /// point where the publisher answered but part of the answer could not be
  /// read.
  ///
  /// Why it exists (HER-trace): the `AdvisoryProvider` contract says an empty
  /// list means no advisories are active at the point. Discarding entries this
  /// adapter could not parse and returning the survivors would present a
  /// partial read as a complete one — a silent under-warn in exactly the
  /// degraded conditions this catalog exists for, where the discarded entry may
  /// have been the black-ice alert. The aggregator only records a provider
  /// failure when a provider throws, and a non-empty result is correctly
  /// returned rather than thrown, so the signal is carried in-band.
  ///
  /// Shaped so it cannot masquerade as a hazard, following the sibling
  /// `condition_aggregator_jma` precedent:
  ///   * `severity` = [AdvisorySeverity.minor] — below the umbrella's
  ///     `isHighImpact` threshold, so an integrator rendering only
  ///     driver-actionable items can filter it out;
  ///   * `certainty` / `urgency` = `unknown` — it is not a weather event;
  ///   * `eventClass` = [kOwmRoadRiskIncompleteReadEventClass] — an identity no
  ///     publisher emits;
  ///   * `effective` / `expires` = null — an availability notice has no
  ///     validity window, and inventing one would fabricate a freshness this
  ///     adapter does not have.
  ///
  /// Availability to the caller is guaranteed; what a driver is shown is the
  /// integrator's rendering choice.
  static Advisory buildIncompleteReadNotice({
    required OwmRoadRiskRead read,
    required double latitude,
    required double longitude,
  }) {
    final n = read.unreadableEntries;
    final text =
        'OpenWeatherMap Road Risk answered for this point, but $n '
        '${n == 1 ? 'entry' : 'entries'} in the response could not be read. '
        'Any road risk described by those entries is not represented here. '
        'Causes: ${read.unreadableCauses.join('; ')}.';
    return Advisory(
      source: AdvisorySource.other,
      eventClass: kOwmRoadRiskIncompleteReadEventClass,
      severity: AdvisorySeverity.minor,
      certainty: AdvisoryCertainty.unknown,
      urgency: AdvisoryUrgency.unknown,
      areaDescription:
          'OpenWeatherMap Road Risk near ${latitude.toStringAsFixed(4)}, '
          '${longitude.toStringAsFixed(4)}.',
      effective: null,
      expires: null,
      headline: text,
      description: text,
    );
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
      severity: severityFromAlert(alert),
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
