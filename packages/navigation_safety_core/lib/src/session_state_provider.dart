/// Optional driving-session-state signal source for
/// cumulative-fatigue-aware threshold tuning.
///
/// `SessionStateProvider` is the integrator-supplied interface that
/// surfaces a current [SessionState] (consecutive-driving-days +
/// cumulative-fatigue classification) to the
/// `NavigationSafetyConfig.forDriverContext` factory. The state is an
/// advisory input consumed for threshold tuning at the warning-tier
/// visibility floor; it does NOT actuate the vehicle and does NOT
/// modulate alert severity.
///
/// **Caution-add-only invariant** (load-bearing): when a session
/// state is supplied, the factory may make warning thresholds fire
/// EARLIER than the per-profile baseline + live-context floor; NEVER
/// later. The mapping from [CumulativeFatigueClass] to threshold
/// adjustment is monotonic in the caution-add direction:
/// `rested` → no-op; `mild` / `accumulated` / `severe` → progressively
/// earlier-warn floors. Returning `null` means the integrator does not
/// have a session-state signal in this trip; the factory falls back
/// to the per-profile + live-context baseline.
///
/// **Severity-not-profile invariant** (load-bearing): session-state
/// adjusts warning TIMING only (warn-earlier-floors). It does NOT
/// modify the score-floor tiers (`safeScoreFloor` / `infoScoreFloor` /
/// `warningScoreFloor`), the critical thresholds, or the
/// alerts-per-minute cap. Per-profile differentiation in delivery
/// remains in `AlertExplainer` + `AlertDensityThrottle`; session-state
/// lives entirely in the threshold-tuning layer.
///
/// **Driver-always-drives invariant** (load-bearing): the provider
/// returns advisory signals; it does NOT close a control loop and
/// does NOT actuate the vehicle. Returning `severe` does not put the
/// vehicle into a degraded mode; it only sharpens the warning-tier
/// visibility floor.
///
/// **Privacy + persistence**: this package does NOT persist session
/// state. The integrator owns persistence (consecutive-day counter
/// across trips, day-rollover semantics, opt-in scope) and the
/// privacy-class boundary. The package consumes only the typed value
/// at the factory call-site.
///
/// Typical wiring:
///
/// ```dart
/// class MySessionStateProvider implements SessionStateProvider {
///   @override
///   SessionState? get sessionState => SessionState(
///         consecutiveDrivingDays: integratorTracker.daysInARow,
///         cumulativeFatigue: integratorTracker.classifyFatigue(),
///       );
/// }
///
/// final config = NavigationSafetyConfig.forDriverContext(
///   driverContext,
///   environmentalContext: ctx,
///   sessionState: provider.sessionState,
/// );
/// ```
library;

import 'package:equatable/equatable.dart';

/// Cumulative-fatigue classification derived by the integrator from
/// consecutive-driving-day history (or other integrator-class
/// fatigue-tracking signal). The four classes are advisory inputs
/// consumed for threshold tuning.
///
/// **Day-threshold magnitudes are UNVERIFIED**: the boundaries
/// (`rested` 0–2 / `mild` 3–4 / `accumulated` 5–6 / `severe` 7+) are
/// **design-default hypotheses** pending fleet-class field
/// measurement. See `KNOWN_LIMITATIONS.md` (session-state section,
/// 0.10.0) for the disclosure.
enum CumulativeFatigueClass {
  /// 0–2 consecutive driving days. No cumulative-fatigue caution
  /// adjustment applied.
  rested,

  /// 3–4 consecutive driving days. Small caution-adding adjustment.
  mild,

  /// 5–6 consecutive driving days. Moderate caution-adding
  /// adjustment.
  accumulated,

  /// 7+ consecutive driving days. Largest caution-adding adjustment
  /// in the per-class table.
  severe,
}

/// Immutable snapshot of the driving-session-state for a single
/// `NavigationSafetyConfig.forDriverContext` call.
///
/// Pairs the consecutive-driving-day count (raw integrator-tracked
/// signal) with the [cumulativeFatigue] classification (integrator-
/// derived bucket). The factory consumes [cumulativeFatigue] for the
/// threshold adjustment; [consecutiveDrivingDays] is carried for the
/// integrator's own logging / analytics needs and for the
/// `LoomFitTelemetry` correlation surface.
///
/// **UNVERIFIED-magnitude flag**: the day-thresholds dividing the
/// four [CumulativeFatigueClass] buckets are **design-default
/// hypotheses** pending fleet-class field measurement. See
/// `KNOWN_LIMITATIONS.md` (session-state section, 0.10.0).
class SessionState extends Equatable {
  /// Number of consecutive days the driver has been driving (0 means
  /// today is the first day in the run; `>= 7` means the driver has
  /// been on the road every day for at least a week). Integrator
  /// owns the tracker; semantics (gap-tolerance, day-rollover-time)
  /// are integrator-defined.
  final int consecutiveDrivingDays;

  /// Integrator-derived cumulative-fatigue classification. Determines
  /// the threshold-adjustment magnitude applied by
  /// `NavigationSafetyConfig.forDriverContext`. See
  /// [CumulativeFatigueClass] for class semantics and the
  /// UNVERIFIED-magnitude flag on the day-thresholds.
  final CumulativeFatigueClass cumulativeFatigue;

  /// Construct a session-state snapshot. [consecutiveDrivingDays]
  /// must be `>= 0`; the factory throws [RangeError] otherwise.
  const SessionState({
    required this.consecutiveDrivingDays,
    required this.cumulativeFatigue,
  });

  @override
  List<Object?> get props => [consecutiveDrivingDays, cumulativeFatigue];

  @override
  bool get stringify => true;
}

/// Integrator-supplied source of the current [SessionState].
///
/// Implement this interface in the consuming app to surface the
/// session-state signal (when available) to the threshold-config
/// factory. Return `null` when the integrator does not have a
/// session-state signal in this trip; the factory falls back to the
/// per-profile + live-context baseline.
///
/// See library documentation for the caution-add-only +
/// severity-not-profile + driver-always-drives invariants and the
/// privacy + persistence note (the integrator owns persistence; the
/// package does not persist).
abstract class SessionStateProvider {
  /// Returns the current [SessionState] (consecutive-driving-days +
  /// cumulative-fatigue classification). Return `null` when no
  /// session-state signal is available; thresholds fall back to the
  /// per-profile + live-context baseline.
  SessionState? get sessionState;
}
