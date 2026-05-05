/// Optional self-assessed-confidence signal source for cap-tightening
/// (and cap-loosening-with-confirmation) threshold tuning.
///
/// `ConfidenceProvider` is the integrator-supplied interface that
/// surfaces the driver's self-assessed [Confidence] to the
/// `NavigationSafetyConfig.forDriverContext` factory. The signal is
/// an advisory input consumed for the alerts-per-minute cap; it does
/// NOT actuate the vehicle and does NOT modulate alert severity.
///
/// **Cap-override-with-confirmation pattern** (load-bearing for the
/// driver-always-drives invariant):
///
/// - `Confidence.low` → automatically TIGHTENS the
///   alerts-per-minute cap (caution-add direction; the
///   less-confident driver gets fewer advisory alerts per minute to
///   reduce overload).
/// - `Confidence.medium` → no-op (no cap modification).
/// - `Confidence.high` → does NOT auto-loosen the cap. The integrator
///   must build a confirmation surface (e.g. an explicit "I am
///   high-confidence on this route" toggle) and set
///   [isHighConfidenceConfirmed] to `true` ONLY after the driver has
///   affirmatively confirmed. Without explicit integrator-supplied
///   confirmation (`isHighConfidenceConfirmed == false`),
///   `Confidence.high` is treated as `Confidence.medium` (no cap
///   modification). The driver-always-drives invariant requires that
///   cap-loosening NEVER auto-fires from a high-confidence reading
///   alone; the driver must affirmatively confirm.
///
/// **Caution-add-only invariant** (load-bearing): the cap-tighten
/// direction (lower alertsPerMinuteCap) is a caution-adding
/// adjustment. The cap-loosen direction (higher alertsPerMinuteCap)
/// is gated by the confirmation flag and is the ONLY exception to
/// the warn-thresholds-only-add-caution invariant; it applies only
/// to the alerts-per-minute cap (rate-limit), never to the warning
/// visibility / temperature floors.
///
/// **Severity-not-profile invariant** (load-bearing): cap modification
/// adjusts ALERT DENSITY only. It does NOT modify the score-floor
/// tiers (`safeScoreFloor` / `infoScoreFloor` / `warningScoreFloor`),
/// the critical thresholds, the warning visibility / temperature
/// floors, or the critical-bypass behaviour
/// (`AlertSeverity.critical` always fires regardless of cap).
///
/// **Driver-always-drives invariant** (load-bearing): the provider
/// returns advisory signals consumed for threshold tuning. It does
/// NOT actuate the vehicle and NOT close a control loop. The
/// confirmation flag mechanism preserves the driver's affirmative
/// agency over cap-loosening: the system never auto-relaxes the
/// safety cap on the basis of a high-confidence reading alone; the
/// driver confirms.
///
/// Typical wiring:
///
/// ```dart
/// class MyConfidenceProvider implements ConfidenceProvider {
///   @override
///   Confidence? get confidence => myUiState.selfReportedConfidence;
///
///   @override
///   bool get isHighConfidenceConfirmed =>
///       myUiState.driverConfirmedHighConfidenceToggle;
/// }
///
/// final config = NavigationSafetyConfig.forDriverContext(
///   driverContext,
///   environmentalContext: ctx,
///   confidence: provider.confidence,
///   isHighConfidenceConfirmed: provider.isHighConfidenceConfirmed,
/// );
/// ```
library;

/// Driver self-assessed confidence classification. Three classes
/// chosen for cognitive accessibility on a single in-vehicle UI
/// surface; integrators may collect a finer-grained signal upstream
/// and bucket into these classes at the call-site.
///
/// **UNVERIFIED-magnitude flag**: the cap-tighten magnitude applied
/// for `Confidence.low` is a **design-default hypothesis** pending
/// field-measurement validation. See `KNOWN_LIMITATIONS.md`
/// (confidence-provider section, 0.10.0) for the disclosure.
enum Confidence {
  /// Driver self-reports high confidence on the current route /
  /// conditions. Cap-loosening applies ONLY when the integrator
  /// explicitly sets `isHighConfidenceConfirmed = true` (driver-
  /// always-drives invariant). Without explicit confirmation, treated
  /// as [Confidence.medium] (no cap modification).
  high,

  /// Driver self-reports medium / nominal confidence. No cap
  /// modification applied.
  medium,

  /// Driver self-reports low confidence (unfamiliar route, novel
  /// conditions, fatigue, etc.). Cap is automatically TIGHTENED to
  /// reduce advisory-alert overload (caution-add direction). No
  /// confirmation flag required for the tightening direction.
  low,
}

/// Integrator-supplied source of the driver's self-assessed
/// [Confidence] signal AND the high-confidence-confirmation flag.
///
/// The two signals together form the cap-override-with-confirmation
/// pattern; see library documentation for the load-bearing
/// driver-always-drives invariant.
///
/// Return `null` from [confidence] when no signal is available; the
/// factory falls back to no cap modification.
abstract class ConfidenceProvider {
  /// Driver's self-assessed confidence classification. Return `null`
  /// when no signal is available; the factory falls back to no cap
  /// modification.
  Confidence? get confidence;

  /// Whether the driver has affirmatively confirmed the
  /// high-confidence reading via an integrator-supplied confirmation
  /// surface (e.g. an explicit toggle). When `false` (the default),
  /// [Confidence.high] is treated as [Confidence.medium] and no cap
  /// modification applies. When `true`, [Confidence.high] is
  /// permitted to loosen the cap.
  ///
  /// **Driver-always-drives invariant**: the system never
  /// auto-relaxes the safety cap from a high-confidence reading
  /// alone; the driver must affirmatively confirm. Returning `true`
  /// without the driver having confirmed is a programmer error.
  bool get isHighConfidenceConfirmed;
}
