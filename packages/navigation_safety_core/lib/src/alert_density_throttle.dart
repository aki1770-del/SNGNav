/// Alert-density throttle for per-profile rate-limiting of advisory
/// alerts (info / warning tiers), with a non-negotiable critical-bypass
/// invariant.
///
/// Why this exists (literature anchors):
///
/// Alarm fatigue is the documented failure mode for systems that fire
/// too many alerts. The medical alarm-fatigue scoping review
/// (PMC12181921) finds >60% of alarms get no timely response and 85%
/// of clinicians report overwhelm. The AAA-FTS ADAS-exposure /
/// driver-workload report extends the same pattern to consumer ADAS:
/// alert density above the driver's tolerance produces desensitization,
/// and a safety-critical alert arriving in a desensitized state can be
/// ignored. arxiv 2410.06388 frames over-warning explicitly as a
/// silent safety failure.
///
/// The throttle's job is to prevent advisory-tier desensitization. Its
/// non-negotiable invariant is that `AlertSeverity.critical` always
/// fires regardless of in-window count. Critical alerts must remain
/// credible; the throttle exists to keep them that way, not to mask
/// them.
///
/// Per-profile cap defaults are literature-anchored (see
/// `defaultCapFor` and the per-cell comments). They are DEFAULTS, not
/// invariants; integrating apps can override via
/// `NavigationSafetyConfig.alertsPerMinuteCapOverride`.
///
/// This is a Pure Dart, advisory-only surface. It does not actuate the
/// vehicle. The throttle decides whether an advisory alert *fires from
/// the package boundary*; the consuming application owns delivery to
/// the driver and retains full responsibility.
library;

import 'alert_severity.dart';
import 'driver_profile.dart';

/// Per-profile alert-density throttle.
///
/// Design rationale:
///
/// - **Failure mode this prevents** — alert fatigue: the app fires more
///   advisory alerts than the driver can process, the driver
///   desensitizes, and a later safety-critical alert lands on a
///   desensitized driver. The throttle stops the over-warning before
///   that desensitization compounds.
/// - **How it works** — per-profile caps are anchored in PMC12181921,
///   PMC7283540, PubMed 16313881, PubMed 22664714, AAA-FTS and
///   arxiv 2410.06388. The cap table in `defaultCapFor` is the
///   recorded decision.
/// - **What it will not do** — it throttles the app, never the driver.
///   Each driver class gets a literature-anchored cap matched to its
///   own reaction-time and overwhelm characteristics; no class is
///   treated as second-tier.
///
/// Maintains a sliding rolling window of fired-alert timestamps and
/// gates new alerts against [alertsPerMinuteCap]. Critical alerts
/// bypass the cap when [bypassForCritical] is true (the default and
/// recommended setting; documented invariant — any future change to
/// this default is a breaking change).
///
/// Edge-case behavior (documented in code comments next to each rule):
///
/// 1. Window is rolling 60s by default (sliding, not fixed). Fixed
///    windows allow a burst at minute boundary that the driver
///    perceives as one event but the arithmetic counts as two minutes.
/// 2. Burst-then-quiet: when in-window count exceeds the cap and a
///    new alert arrives, the new alert is DROPPED (not queued) UNLESS
///    it is `AlertSeverity.critical`. Queued post-cap alerts deliver
///    stale information about a now-passed condition; per the listen-
///    frame substrate, false-stale alerts erode trust faster than
///    missed-info alerts (Bian PubMed 38669900).
/// 3. Critical bypass: see invariant above.
/// 4. Cold-start: the first alert in a session bypasses the window
///    check (no historical context to throttle against).
/// 5. Profile-switch: the rolling window resets when a fresh
///    `forProfile` instance is constructed. Carrying the previous
///    profile's window into a more conservative one would over-
///    throttle; the inverse would under-throttle.
/// 6. Suppression telemetry: `shouldFire` returns the firing decision;
///    a returned `false` for a non-critical alert is the consuming
///    app's signal to log a blame-free, context-rich drop record (per
///    insight #105 — drop-records inform the L8 calibration cycle on
///    whether per-profile caps are actually too sensitive).
class AlertDensityThrottle {
  /// Maximum number of advisory alerts that may fire in a single
  /// rolling [window].
  ///
  /// Must be > 0. Per-profile defaults from literature; see
  /// [defaultCapFor].
  final double alertsPerMinuteCap;

  /// Rolling window duration. Default `Duration(seconds: 60)`. The
  /// window slides — every call to [shouldFire] purges entries older
  /// than `now - window` before evaluating the cap.
  final Duration window;

  /// When true (default and recommended invariant),
  /// `AlertSeverity.critical` alerts always fire regardless of the
  /// in-window count. Critical alerts must remain credible; the
  /// throttle's purpose is preventing advisory-tier desensitization,
  /// not masking high-severity warnings.
  ///
  /// Setting this to false changes the throttle's safety contract;
  /// the documented invariant is that this stays true.
  final bool bypassForCritical;

  // Recorded fire timestamps (mutable). Implementation-detail; tests
  // inspect via `currentWindowCount`.
  final List<DateTime> _firedAt = <DateTime>[];

  /// Construct a throttle with an explicit cap.
  ///
  /// Prefer [AlertDensityThrottle.forProfile] for per-driver-class
  /// defaults; this constructor is for tests and for apps with their
  /// own measured per-population data.
  AlertDensityThrottle({
    required this.alertsPerMinuteCap,
    this.window = const Duration(seconds: 60),
    this.bypassForCritical = true,
  }) {
    if (alertsPerMinuteCap <= 0) {
      throw ArgumentError.value(
        alertsPerMinuteCap,
        'alertsPerMinuteCap',
        'must be > 0',
      );
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(window, 'window', 'must be > Duration.zero');
    }
  }

  /// Construct a throttle with the per-profile literature-anchored
  /// default cap.
  ///
  /// See [defaultCapFor] for the cap-table and per-cell citations.
  factory AlertDensityThrottle.forProfile(DriverProfile profile) {
    return AlertDensityThrottle(alertsPerMinuteCap: defaultCapFor(profile));
  }

  /// Per-profile literature-anchored default alerts/min cap.
  ///
  /// These are the v0.4 defaults; integrating apps can override via
  /// `NavigationSafetyConfig.alertsPerMinuteCapOverride`.
  ///
  /// Per-cell anchors:
  ///
  /// - `professional` — 4.0. Trained drivers; AAA-FTS ADAS-exposure
  ///   report finds professional drivers retain alert-acceptance at
  ///   higher densities. Cap is upper-end; bias toward signal
  ///   preservation.
  /// - `snowZoneExperienced` — 3.0. Standard baseline; experienced
  ///   snow-driver hazard-perception RT ≈ 1.32s (PubMed 16313881).
  /// - `agriculturalForestry` — 2.0. Off-road / extended-shift
  ///   contexts; OSHA 1928 / FAO UNECE-FAO-ILO 2023 forestry literature
  ///   emphasizes systemic fatigue management; lower cap protects
  ///   against shift-end desensitization.
  /// - `noviceUrban` — 1.5. Novice hazard-perception RT 3.58s (PubMed
  ///   16313881) — >2× experienced. Each alert needs longer processing
  ///   time; closer cap protects against queueing-into-overload.
  /// - `ageingRural` — 1.2. Strayer/AAA PMC7283540 — older drivers
  ///   cost +8s eyes-off-road on identical voice formats; AAA-FTS
  ///   ADAS-exposure-and-driver-workload finds older drivers report
  ///   higher overwhelm at given alert density.
  /// - `foreignTouristSnowZone` — 1.0. Combines novice-equivalent
  ///   unfamiliarity (Konstantopoulos PubMed 22664714 novice-fog
  ///   crash-rate elevation) + language-processing overhead (translation
  ///   time during alert reception). Strictest cap.
  static double defaultCapFor(DriverProfile profile) {
    switch (profile) {
      case DriverProfile.professional:
        return 4.0;
      case DriverProfile.snowZoneExperienced:
        return 3.0;
      case DriverProfile.agriculturalForestry:
        return 2.0;
      case DriverProfile.noviceUrban:
        return 1.5;
      case DriverProfile.ageingRural:
        return 1.2;
      case DriverProfile.foreignTouristSnowZone:
        return 1.0;
    }
  }

  /// Returns true if the alert should fire (under cap or
  /// critical-bypass); false if it should be dropped.
  ///
  /// Side-effect: when the alert is permitted to fire, its [now]
  /// timestamp is recorded in the rolling window. Calls to this method
  /// purge entries older than `now - window` before evaluating the
  /// cap.
  ///
  /// Critical-bypass: when [bypassForCritical] is true and [severity]
  /// is `AlertSeverity.critical`, this always returns true and records
  /// the firing timestamp (criticals do consume window slots — they
  /// represent real driver-attention events).
  ///
  /// Cold-start: the first call to this method in a session bypasses
  /// the window check (no historical context to throttle against). The
  /// firing timestamp is still recorded.
  bool shouldFire(DateTime now, AlertSeverity severity) {
    // Purge entries older than `now - window` before any evaluation.
    final cutoff = now.subtract(window);
    _firedAt.removeWhere(
      (t) => t.isBefore(cutoff) || t.isAtSameMomentAs(cutoff),
    );

    // Cold-start: first alert in session bypasses window check.
    if (_firedAt.isEmpty) {
      _firedAt.add(now);
      return true;
    }

    // Critical-bypass: criticals always fire (and still consume a slot).
    if (bypassForCritical && severity == AlertSeverity.critical) {
      _firedAt.add(now);
      return true;
    }

    // Cap evaluation: in-window count strictly less than cap → fire.
    // The cap is a per-window count; .floor() applied to the double
    // cap yields the integer ceiling. With cap = 1.5 and 1 prior
    // alert in window, 1 < 1.5 → fire (and become 2nd); with 2 prior,
    // 2 < 1.5 false → drop (until window slides).
    if (_firedAt.length < alertsPerMinuteCap) {
      _firedAt.add(now);
      return true;
    }

    // Burst-then-quiet: drop the new alert (do not queue).
    return false;
  }

  /// Test-only inspection: number of recorded firings within the
  /// rolling window relative to [now]. Purges expired entries as a
  /// side-effect of evaluation.
  int currentWindowCount(DateTime now) {
    final cutoff = now.subtract(window);
    _firedAt.removeWhere(
      (t) => t.isBefore(cutoff) || t.isAtSameMomentAs(cutoff),
    );
    return _firedAt.length;
  }
}
