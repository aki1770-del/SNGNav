/// Tunable honesty horizons for the localization controller.
library;

/// Configuration for [LocalizationController].
///
/// Every value here is an HONESTY horizon, not a performance knob: they
/// describe how fast we admit uncertainty and when we admit we are lost. The
/// defaults are deliberately conservative for snow-zone / compound-failure use
/// — it is safer to say "lost" early than to show a confident wrong dot.
class LocalizationConfig {
  /// How fast the confidence radius grows per second while dead-reckoning,
  /// in metres per second. This is the documented growth model:
  ///
  ///   radius = lastTrustedAccuracy + driftRate * secondsDead
  ///
  /// where `driftRate` is this value, EXCEPT while the dot is frozen at
  /// last-known (no dead-reckoning seam wired): there the rate is floored by
  /// the last trusted fix's ground speed, so the circle still plausibly
  /// contains a vehicle that kept moving after GPS dropped.
  ///
  /// 2.0 m/s is a conservative default for a slowly drifting inertial / wheel
  /// dead-reckoning solution.
  ///
  /// Must be finite and non-negative (asserted). If a release build (where
  /// asserts are stripped) somehow supplies a garbage value (NaN / negative /
  /// infinite), the controller cannot model uncertainty growth from it, so it
  /// refuses to let it collapse the radius and degrades honestly to `lost`
  /// rather than invent precision.
  final double driftRateMetersPerSecond;

  /// Once the confidence radius exceeds this many metres, the mode becomes
  /// `lost` — the position is too uncertain to present as anything but a guess.
  final double maxTrustworthyRadiusMeters;

  /// Once this many seconds have passed since the last trusted fix, the mode
  /// becomes `lost` regardless of the radius model.
  final double maxDeadReckoningSeconds;

  const LocalizationConfig({
    this.driftRateMetersPerSecond = 2.0,
    this.maxTrustworthyRadiusMeters = 500.0,
    this.maxDeadReckoningSeconds = 120.0,
  })  : assert(driftRateMetersPerSecond >= 0),
        assert(maxTrustworthyRadiusMeters > 0),
        assert(maxDeadReckoningSeconds > 0);
}
