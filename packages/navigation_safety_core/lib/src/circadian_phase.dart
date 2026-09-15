/// Time-of-day circadian-phase classification for driver-state-aware
/// threshold tuning.
///
/// `CircadianPhase` partitions the 24-hour clock into six phases meant
/// to reflect different driver alertness regimes (a recorded decision;
/// no source is cited). Each phase
/// carries a multiplier in `[1.0, 1.5]` that the
/// `NavigationSafetyConfig.forDriverContext` factory applies to the
/// reaction-time-driven warning visibility floor as a caution-adding
/// adjustment.
///
/// The phase boundaries (00:00 / 04:00 / 08:00 / 12:00 / 16:00 / 20:00)
/// are a recorded decision (no source is cited); the multiplier values
/// are **design-default hypotheses**
/// pending field-measurement validation. See `KNOWN_LIMITATIONS.md`
/// (circadian-phase section, 0.10.0) for the UNVERIFIED-magnitude
/// disclosure on every per-phase multiplier.
///
/// **Caution-add-only invariant** (load-bearing): the multiplier is
/// floored at `1.0` (`morning` baseline) and capped at `1.5`
/// (`lateNight` circadian-trough). `1.0` means no adjustment; values
/// `> 1.0` make warning thresholds fire EARLIER than the baseline.
/// The floor holds in every build mode: each multiplier is a fixed
/// value inside this package, and the factory applies a circadian
/// result only when it raises the warning visibility floor, an ordinary
/// `if` that release builds keep. A debug-mode assertion at that site
/// additionally flags a multiplier edited below `1.0`.
///
/// **Severity-not-profile invariant** (load-bearing): the circadian
/// adjustment tunes warning TIMING only (warn-earlier-floors). It does
/// NOT modify the score-floor tiers (`safeScoreFloor` /
/// `infoScoreFloor` / `warningScoreFloor`), the critical thresholds,
/// or the alerts-per-minute cap.
///
/// **Driver-always-drives invariant** (load-bearing): the phase is an
/// advisory input consumed for threshold tuning. It does NOT actuate
/// the vehicle, NOT close any control loop, NOT modulate alert
/// severity. Returning a phase does not change vehicle behaviour; it
/// only sharpens the warning-tier visibility floor for the intended
/// risk windows (circadian trough, post-lunch dip, sleep inertia).
///
/// Typical wiring (integrator-supplied):
///
/// ```dart
/// // oracle:placeholders driverContext, ctx
/// final phase = circadianPhaseFromHour(DateTime.now().hour);
/// final config = NavigationSafetyConfig.forDriverContext(
///   driverContext,
///   environmentalContext: ctx,
///   circadianPhase: phase,
/// );
/// ```
library;

/// Time-of-day partition used by
/// `NavigationSafetyConfig.forDriverContext` to apply a circadian
/// caution-adding multiplier to the warning-tier visibility floor.
///
/// Phases are advisory inputs consumed for threshold tuning. They do
/// NOT actuate the vehicle and do NOT modulate alert severity. See
/// library documentation for invariants and the UNVERIFIED-magnitude
/// flag on the per-phase multiplier values.
enum CircadianPhase {
  /// 04:00 – 07:59 — sleep inertia window. Cognitive performance
  /// recovers gradually after waking; the window is meant to reflect
  /// slower reactions after waking (no source is cited). Multiplier
  /// `1.2`.
  earlyMorning,

  /// 08:00 – 11:59 — peak alertness window. Used as the baseline
  /// (multiplier `1.0`); no caution-adding adjustment applied.
  morning,

  /// 12:00 – 15:59 — post-lunch dip. The window is meant to reflect a
  /// mild post-lunch alertness dip (no source is cited). Multiplier
  /// `1.1`.
  afternoon,

  /// 16:00 – 19:59 — fatigue accumulation. The window is meant to
  /// reflect end-of-workday load and fatigue building through the day
  /// (no source is cited). Multiplier `1.05`.
  evening,

  /// 20:00 – 23:59 — circadian-low. Evening-into-night transition;
  /// alertness declines toward the night-time minimum. Multiplier
  /// `1.3`.
  night,

  /// 00:00 – 03:59 — circadian-trough (highest risk). The
  /// chronobiological low-point; the window is meant to reflect the
  /// overnight alertness low (no source is cited). Multiplier `1.5`
  /// (cap).
  lateNight,
}

/// Caution-adding multiplier extension for [CircadianPhase].
///
/// Values are **design-default hypotheses** pending field-measurement
/// validation; see `KNOWN_LIMITATIONS.md` (circadian-phase section,
/// 0.10.0) for the UNVERIFIED-magnitude flag. The multiplier is
/// always in `[1.0, 1.5]`; `1.0` means no adjustment, `1.5` is the
/// `lateNight` cap.
extension CircadianPhaseMultiplier on CircadianPhase {
  /// Caution-adding multiplier applied to the warning-tier visibility
  /// floor by `NavigationSafetyConfig.forDriverContext`. Always
  /// `>= 1.0` (caution-add-only floor) and `<= 1.5` (`lateNight`
  /// cap).
  double get multiplier {
    switch (this) {
      case CircadianPhase.morning:
        return 1.0;
      case CircadianPhase.evening:
        return 1.05;
      case CircadianPhase.afternoon:
        return 1.1;
      case CircadianPhase.earlyMorning:
        return 1.2;
      case CircadianPhase.night:
        return 1.3;
      case CircadianPhase.lateNight:
        return 1.5;
    }
  }
}

/// Helper for mapping a 24-hour clock hour (0..23) to the
/// corresponding [CircadianPhase]. Integrators that already hold a
/// hour-of-day signal can use this rather than a custom switch.
///
/// Throws [RangeError] if [hour] is outside `[0, 23]`.
CircadianPhase circadianPhaseFromHour(int hour) {
  if (hour < 0 || hour > 23) {
    throw RangeError.range(hour, 0, 23, 'hour');
  }
  if (hour < 4) return CircadianPhase.lateNight;
  if (hour < 8) return CircadianPhase.earlyMorning;
  if (hour < 12) return CircadianPhase.morning;
  if (hour < 16) return CircadianPhase.afternoon;
  if (hour < 20) return CircadianPhase.evening;
  return CircadianPhase.night;
}
