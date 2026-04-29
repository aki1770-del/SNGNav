/// Speed-dependent visibility threshold formula.
///
/// Per-profile baseline visibility thresholds are tuned for typical
/// commute speeds. At higher speeds, reaction-time distance and
/// braking distance both grow, and a fixed visibility threshold can
/// leave no room for the driver to perceive, decide, and stop. This
/// helper raises the warning-visibility floor when current speed is
/// known, while preserving the baseline as a lower bound.
///
/// Returned distance is `max(profileBase, RT_distance + braking_distance)`,
/// where `RT_distance = reactionTime × speed` and
/// `braking_distance = speed^2 / (2 × deceleration)`. Both follow
/// standard kinematics for a vehicle decelerating to a stop.
///
/// Reaction-time literature anchors the per-profile defaults:
///
/// - **Hazard-perception RT for novice vs experienced drivers** —
///   novice 3.58s, experienced 1.32s, per
///   [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/).
/// - **Trait-state framing of reaction time** — Regan, Hallett &
///   Gordon 2011 ([PMC4001671](https://pmc.ncbi.nlm.nih.gov/articles/PMC4001671/))
///   distinguishes trait reaction-time (driver class) from state
///   reaction-time (drowsy / distracted). This package today encodes
///   trait only; per-profile defaults below assume an alert state.
///
/// Braking-deceleration default is 5.5 m/s², a typical passenger-car
/// dry-pavement value. For snow / ice surfaces the consumer should
/// pass a lower value (≈3.0 m/s² for compacted snow; ≈1.5 m/s² for
/// glare ice). Surface friction coefficient is the dominant variable;
/// no single default fits every road condition.
///
/// Per-profile reaction-time defaults (consumer-supplied; this helper
/// does not pick a profile RT — it accepts the RT as a parameter):
///
/// - `ageingRural` ≈ 2.5s — older drivers; published distribution.
/// - `noviceUrban` ≈ 3.58s — PubMed 16313881 hazard-perception value.
/// - `snowZoneExperienced` ≈ 1.8s — alert defensive-driving culture
///   (UNVERIFIED specific cite; conservative anchor between
///   experienced 1.32s and a snow-context margin).
/// - `professional` ≈ 1.5s — trained reaction; UNVERIFIED specific
///   cite for the 1.5s magnitude.
/// - `agriculturalForestry` ≈ 2.0s — typical adult; UNVERIFIED.
/// - `foreignTouristSnowZone` ≈ 3.5s — matches novice behaviour in
///   unfamiliar conditions; UNVERIFIED specific cite.
///
/// Values marked UNVERIFIED are reasonable defaults pending field
/// validation; see `KNOWN_LIMITATIONS.md` for the calibration discipline.
library;

import 'dart:math' as math;

/// Compute a speed-adjusted visibility threshold in metres.
///
/// Returns the larger of [profileBaseMeters] and the sum of
/// reaction-time distance and braking distance for the given
/// [speedMps] and [driverReactionTimeSeconds]. The per-profile
/// baseline acts as a lower bound: context can only raise the
/// threshold (warn earlier), not lower it.
///
/// [brakingDecelerationMps2] defaults to 5.5 m/s² (typical dry
/// pavement). For snow / ice surfaces, pass a lower value reflecting
/// the surface friction coefficient.
///
/// Throws [ArgumentError] if any numeric input is negative or if
/// [brakingDecelerationMps2] is non-positive.
double computeSpeedAdjustedVisibilityMeters({
  required double profileBaseMeters,
  required double speedMps,
  required double driverReactionTimeSeconds,
  double brakingDecelerationMps2 = 5.5,
}) {
  if (profileBaseMeters < 0) {
    throw ArgumentError.value(
      profileBaseMeters,
      'profileBaseMeters',
      'must be non-negative',
    );
  }
  if (speedMps < 0) {
    throw ArgumentError.value(speedMps, 'speedMps', 'must be non-negative');
  }
  if (driverReactionTimeSeconds < 0) {
    throw ArgumentError.value(
      driverReactionTimeSeconds,
      'driverReactionTimeSeconds',
      'must be non-negative',
    );
  }
  if (brakingDecelerationMps2 <= 0) {
    throw ArgumentError.value(
      brakingDecelerationMps2,
      'brakingDecelerationMps2',
      'must be positive',
    );
  }

  final reactionDistance = driverReactionTimeSeconds * speedMps;
  final brakingDistance = (speedMps * speedMps) / (2.0 * brakingDecelerationMps2);
  final required = reactionDistance + brakingDistance;

  return math.max(profileBaseMeters, required);
}
