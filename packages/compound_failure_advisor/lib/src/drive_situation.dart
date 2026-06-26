import 'mirror_enums.dart';

/// The in-drive situation, by value, at one instant.
///
/// One immutable value object assembled by the integrator from the bands that
/// the catalog already publishes — `localization_fallback`'s
/// `LocalizationEstimate`, a `pretrip_source_*` `VisibilityObservation`, and
/// the `condition_aggregator` advisory it already selected. This package reads
/// these values; it never fetches, estimates, classifies, or owns a clock.
///
/// Every field is defined for its degenerate inputs — `null`,
/// [double.infinity], [double.nan], and negative numbers — because the advisor
/// is total: it clamps and degrades conservatively, it never throws.
class DriveSituation {
  /// Creates an immutable in-drive situation.
  const DriveSituation({
    required this.positionTrust,
    required this.confidenceRadiusMeters,
    required this.secondsSinceTrustedFix,
    required this.hasPosition,
    required this.visibilityMeters,
    required this.visibilityAgeSeconds,
    required this.advisorySeverity,
    required this.speedMetersPerSecond,
  });

  // --- position (from a LocalizationEstimate) ---

  /// `estimate.mode` mapped through one switch at the seam.
  final PositionTrust positionTrust;

  /// `estimate.confidenceRadiusMeters` — "the dot could be anywhere in this
  /// circle". Grows-only while untrusted, so caution can only ever rise while
  /// degraded. [double.nan] / negative is treated as the worst for the current
  /// trust tier, never plotted.
  final double confidenceRadiusMeters;

  /// `estimate.secondsSinceTrustedFix`. May be [double.infinity] (never had a
  /// trusted fix this session).
  final double secondsSinceTrustedFix;

  /// `estimate.hasPosition`. `false` = no dot at all (bootstrap / NaN);
  /// dominates the position concern.
  final bool hasPosition;

  // --- visibility (from a VisibilityObservation) ---

  /// `observation.meters`, OR `null` = NO real reading in hand. `null` is a
  /// first-class unknown, never coerced to "clear".
  final double? visibilityMeters;

  /// `now − observation.measuredAt` in seconds; `null` = unknown age. Beyond
  /// the freshness window the reading is treated as unknown, not trusted.
  final double? visibilityAgeSeconds;

  // --- area advisory (the single most-severe in-area advisory, pre-selected) ---

  /// `null` = no advisory in force. This package does NOT aggregate advisories.
  final AdvisoryLevel? advisorySeverity;

  // --- her motion ---

  /// Current ground speed in m/s, or `null` if unknown. Unknown speed never
  /// withholds caution — it is recorded as an [Unknown] and the model degrades
  /// to the position×visibility core.
  final double? speedMetersPerSecond;
}
