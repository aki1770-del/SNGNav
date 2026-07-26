/// The catalyst that lets `compound_failure_advisor` react on the signals the
/// catalog already produces.
///
/// `compound_failure_advisor` is intentionally zero-dependency: it mirrors the
/// enum shapes it needs so it never inherits a runtime dependency tree and
/// stays 32-bit-ARM friendly. The price of that decoupling is a seam — someone
/// has to map `localization_fallback`'s `LocalizationMode` onto the advisor's
/// `PositionTrust`, and `condition_aggregator`'s `AdvisorySeverity` onto
/// `AdvisoryLevel`. This package is that seam, done once, correctly, and tested,
/// so every integrator does NOT re-derive it — and cannot get the one
/// safety-critical case wrong.
///
/// The safety-critical case: `LocalizationMode.deadReckoning` maps to
/// `PositionTrust.degraded`, NOT to `trusted`. A naive hand-mapping that treats
/// "still emitting a position" as trusted would silently suppress the compound
/// caution at the exact moment GPS is gone and she is dead-reckoning through a
/// tunnel in snow — the D3 worst case. This library makes that mapping
/// canonical.
///
/// Pure Dart. Total and deterministic — like the advisor it feeds, it never
/// throws, owns no clock, and does no IO. It maps values across a seam; it does
/// not fetch, estimate, classify, or aggregate. Freshness (visibility age) is
/// the caller's clock, passed in — this library stays clockless on purpose.
library;

export 'src/fuse.dart';

/// Spatial hazard-zone advisory state machine, refactored from the nav2
/// ZoneParameterFilter (#6104): HER position selects a hazard zone whose advisory
/// is offered to her (display-only), holding caution on an uncertain fix.
export 'src/advisory_zone_advisor.dart';
