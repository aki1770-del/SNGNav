/// Trust in the current position estimate.
///
/// A 1:1 mirror of `localization_fallback`'s `LocalizationMode`. It is restated
/// locally — NOT imported — so this advisory carries zero runtime dependencies
/// and the integrator maps across the seam with one explicit switch (see the
/// README composition example). `localization_fallback` publishes on its own
/// cadence; a hard dependency would couple that cadence to this package and
/// break the zero-dep / 32-bit-ARM contract.
enum PositionTrust {
  /// A trusted GPS fix — the dot is where it says it is, within its radius.
  trusted,

  /// The fix is questionable (e.g. multipath suspected); not yet abandoned.
  suspect,

  /// No trusted fix; the position is being carried by dead-reckoning and the
  /// confidence radius is growing.
  degraded,

  /// Position is lost — there is no usable fix at all.
  lost,
}

/// Severity of the single most-severe in-area advisory the integrator has
/// already selected.
///
/// A 1:1 mirror of `condition_aggregator`'s `AdvisorySeverity`. This package
/// does NOT aggregate advisories; it consumes the one the caller chose. The
/// caller's `unknown`/none maps to a `null` `advisorySeverity`, never to a
/// value here — "no advisory in force" is the absence of this enum, not one of
/// its members.
enum AdvisoryLevel {
  /// Minor advisory — treated as no escalation.
  minor,

  /// Moderate advisory — a single rung of concern.
  moderate,

  /// Severe advisory — escalates the fused caution by one.
  severe,

  /// Extreme advisory — strong enough to reach the caution ceiling alone,
  /// mirroring a lost position or a whiteout each reaching it alone.
  extreme,
}
