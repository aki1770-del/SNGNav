import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:localization_fallback/localization_fallback.dart';

/// Assembles a [DriveSituation] for [adviseInDrive] from the values the catalog
/// already produces.
///
/// - [estimate] — the current `localization_fallback` [LocalizationEstimate].
///   Its `mode`, `confidenceRadiusMeters`, `secondsSinceTrustedFix`, and
///   `hasPosition` flow straight through; the advisor is total and handles any
///   degenerate radius / time itself, so this seam does not clamp them.
/// - [advisory] — the single most-severe in-area `condition_aggregator`
///   [Advisory] the caller has already selected, or `null` for none. Its
///   `severity` is mapped through [advisoryLevelOf]; `unknown`/absent both
///   become a `null` [DriveSituation.advisorySeverity] ("no advisory in force"),
///   never a value.
/// - [visibilityMeters] / [visibilityAgeSeconds] — a real reading and its age,
///   both `null` when unknown. This library owns no clock: the caller computes
///   the age (e.g. `now.difference(observation.measuredAt).inSeconds`) and
///   passes it. `null` visibility is a first-class unknown, never coerced.
/// - [speedMetersPerSecond] — her current ground speed, or `null` if unknown.
///
/// Total and deterministic: it never throws, never reaches for a clock, and
/// performs no IO. It maps values across the advisor's zero-dependency seam and
/// nothing more.
DriveSituation fuseDriveSituation({
  required LocalizationEstimate estimate,
  Advisory? advisory,
  double? visibilityMeters,
  double? visibilityAgeSeconds,
  double? speedMetersPerSecond,
}) {
  return DriveSituation(
    positionTrust: positionTrustOf(estimate.mode),
    confidenceRadiusMeters: estimate.confidenceRadiusMeters,
    secondsSinceTrustedFix: estimate.secondsSinceTrustedFix,
    hasPosition: estimate.hasPosition,
    visibilityMeters: visibilityMeters,
    visibilityAgeSeconds: visibilityAgeSeconds,
    advisorySeverity: advisoryLevelOf(advisory?.severity),
    speedMetersPerSecond: speedMetersPerSecond,
  );
}

/// The canonical `localization_fallback` -> `compound_failure_advisor` position
/// seam.
///
/// The one case that carries HER's safety: [LocalizationMode.deadReckoning] —
/// GPS is gone and the dot is being carried by dead reckoning with a growing
/// radius — maps to [PositionTrust.degraded], NOT `trusted`. Mapping it to
/// `trusted` (because a position is still being emitted) would suppress the
/// compound caution exactly when she has lost GPS in snow. Kept here, tested,
/// so no hand-mapping gets it wrong.
PositionTrust positionTrustOf(LocalizationMode mode) {
  switch (mode) {
    case LocalizationMode.gpsTrusted:
      return PositionTrust.trusted;
    case LocalizationMode.gpsSuspect:
      return PositionTrust.suspect;
    case LocalizationMode.deadReckoning:
      return PositionTrust.degraded;
    case LocalizationMode.lost:
      return PositionTrust.lost;
  }
}

/// The canonical `condition_aggregator` -> `compound_failure_advisor` advisory
/// seam.
///
/// The two "unknown-shaped" inputs are NOT the same and must not be aliased:
///
/// - `null` — the caller passed no [Advisory] at all. Genuinely "no advisory in
///   force" -> `null` [AdvisoryLevel].
/// - [AdvisorySeverity.unknown] — an advisory IS in force, but its severity
///   token could not be graded. This is `condition_aggregator`'s parse-fail /
///   forward-compat sink (`_severityFromName` returns `unknown` for a missing,
///   non-string, or unrecognized token on an otherwise complete advisory). It
///   is a known-unknown hazard, NOT a non-event: a live warning we cannot
///   classify must never silently vanish. It floors to [AdvisoryLevel.moderate]
///   — one rung of concern with a reason emitted downstream — conservative
///   enough to keep the concern, restrained enough not to slam an ungradable
///   minor notice to the ceiling. (Note: `minor` maps below the advisor's
///   escalation floor, so a lower floor would drop the concern entirely.)
///
/// This is the one place the seam deliberately does NOT follow the advisor's
/// mirror-enum note that "the caller's unknown maps to null": that note assumes
/// `unknown == absent`, which the `condition_aggregator` source contradicts —
/// there, `unknown` only ever rides a real, constructed advisory. The remaining
/// graded severities map one-to-one.
AdvisoryLevel? advisoryLevelOf(AdvisorySeverity? severity) {
  switch (severity) {
    case null:
      return null;
    case AdvisorySeverity.unknown:
      return AdvisoryLevel.moderate;
    case AdvisorySeverity.minor:
      return AdvisoryLevel.minor;
    case AdvisorySeverity.moderate:
      return AdvisoryLevel.moderate;
    case AdvisorySeverity.severe:
      return AdvisoryLevel.severe;
    case AdvisorySeverity.extreme:
      return AdvisoryLevel.extreme;
  }
}
