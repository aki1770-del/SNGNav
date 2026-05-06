/// Frame-timing budget tracker for tile-render advisory cognitive-load
/// management.
///
/// Why this exists:
///
/// Offline-tile rendering competes with the rest of the navigation HMI
/// for the per-frame budget. When tile resolution / decoding /
/// projection sustains over the per-frame budget, the integrator HMI
/// loses headroom to render the safety overlay (snow particle, route
/// shift, alert sheet) at responsive cadence. This tracker exposes the
/// per-frame consumption against a per-cohort budget so the integrator
/// can lighten render-load (drop fidelity, defer non-essential layers,
/// soften animation) before the budget is exhausted.
///
/// **Advisory not control.** The tracker emits `BudgetWarning` and
/// `BudgetExhausted` records on a broadcast stream the integrator may
/// subscribe to. The package mounts no actuator, no automatic input
/// suppression, no driver lockout. The driver always drives; the
/// tracker only reports.
///
/// **Caution-add-only invariant** (load-bearing): per-cohort budget
/// allocation may only be MORE LENIENT (= LARGER frame-time allowance =
/// LOWER frame-rate accepted = MORE caution toward visual-cognitive-
/// margin) than the baseline 16ms. A debug-mode runtime assert in
/// [PerformanceBudgetConfig.forProfile] verifies the per-cohort budget
/// is `>=` the 16ms baseline; in release builds the assert is elided
/// per Dart `assert` semantics.
///
/// **Severity-not-profile invariant**: the budget tracker is timing-
/// class only. It adjusts when the integrator HMI lightens render-load;
/// it does NOT adjust alert severity, score floors, or critical
/// thresholds. Critical alerts in `navigation_safety` retain their
/// critical-bypass invariant regardless of frame-budget state.
///
/// **Driver-always-drives invariant**: the tracker is presentation-
/// class only. The integrator may dim a non-essential layer when
/// `BudgetWarning` fires, but the package itself does not modify any
/// driver-facing surface or vehicle state.
///
/// **Per-cohort budget defaults** (UNVERIFIED-magnitude design-default-
/// hypothesis pending field-measurement validation):
///
/// - `professional`, `snowZoneExperienced`, `agriculturalForestry` →
///   16ms (60fps target; baseline; experienced cohorts).
/// - `noviceUrban` → 18ms (~55fps; mild margin).
/// - `ageingRural` → 22ms (~45fps; visual-cognitive-margin per
///   age-group reaction-time literature; conservative-only).
/// - `foreignTouristSnowZone` → 22ms (~45fps; cognitive-margin for
///   unfamiliar context; conservative-only).
///
/// All per-cohort values are LARGER than 16ms (= MORE LENIENT = MORE
/// caution-add direction). Lower per-cohort budgets are caught by the
/// runtime assert.
///
/// Typical wiring:
///
/// ```dart
/// final tracker = PerformanceBudget(
///   config: PerformanceBudgetConfig.forProfile(DriverProfile.ageingRural),
/// );
/// tracker.budgetEvents.listen((event) {
///   if (event is BudgetWarning) {
///     // integrator-class HMI: drop non-essential layer
///   } else if (event is BudgetExhausted) {
///     // integrator-class HMI: simplify display, defer animation
///   }
/// });
///
/// // From the Flutter SchedulerBinding the integrator wires up:
/// tracker.record(timing); // FrameTiming from
///                         // SchedulerBinding.instance.addTimingsCallback
/// ```
library;

import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:equatable/equatable.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Reason a budget reset was requested by the integrator.
///
/// Reset is integrator-owned at v1 (caution-add-only — never auto-
/// relax). The reason field is informational and may be used by the
/// integrator's own analytics.
enum BudgetResetReason {
  /// Render-pipeline change (e.g. layer set rebuilt, route segment
  /// transitioned) where prior consumption is no longer representative.
  renderCycleStart,

  /// Render-pipeline halted (e.g. map dismissed, app paused).
  renderCycleEnd,

  /// Long pause detected (e.g. integrator detected idle period).
  longPause,

  /// Integrator explicitly requested reset (e.g. user-initiated).
  explicit,
}

/// Configuration for the per-frame render-time budget.
///
/// **Anchor**: Flutter / Skia 60fps target = 16.67ms / frame budget
/// before jank. The 16ms-floor baseline is published-anchor; the
/// per-cohort lenient-direction defaults are design-default hypotheses
/// pending field-measurement validation (per-cohort visual-cognitive-
/// margin not yet anchored in a published study mapping
/// driver-class to optimal-frame-rate-tolerance specifically).
class PerformanceBudgetConfig extends Equatable {
  /// Per-frame budget. Default 16ms ≈ 60fps target.
  final Duration frameBudget;

  /// Threshold ratio at which `BudgetWarning` fires. Default 0.75
  /// (warning when 75% of the budget has been consumed = 25% remains).
  final double warningRatio;

  /// Number of consecutive over-budget frames required before
  /// `BudgetExhausted` fires. Single-frame jank is normal; sustained
  /// over-budget consumption is the budget-exhaustion signal.
  /// Default 5 frames (~83ms at 60fps).
  final int sustainedFrames;

  /// Baseline budget against which per-cohort budgets are compared in
  /// the caution-add-only invariant. Equal to 60fps target.
  static const Duration baselineFrameBudget = Duration(microseconds: 16667);

  const PerformanceBudgetConfig({
    this.frameBudget = baselineFrameBudget,
    this.warningRatio = 0.75,
    this.sustainedFrames = 5,
  })  : assert(warningRatio > 0.0 && warningRatio < 1.0,
            'warningRatio must be in (0.0, 1.0)'),
        assert(sustainedFrames >= 1,
            'sustainedFrames must be >= 1');

  /// Per-cohort lenient-direction defaults.
  ///
  /// **Caution-add-only invariant**: every returned config has a
  /// `frameBudget` `>=` 16ms baseline. Lower-than-baseline values
  /// would relax the visual-cognitive-margin direction and are
  /// rejected at runtime via debug-mode assertion.
  ///
  /// Magnitudes are UNVERIFIED-magnitude design-default-hypothesis
  /// (see library doc). Per-population calibration deferred pending
  /// fleet-class field measurement.
  factory PerformanceBudgetConfig.forProfile(DriverProfile profile) {
    final budget = switch (profile) {
      DriverProfile.professional => baselineFrameBudget,
      DriverProfile.snowZoneExperienced => baselineFrameBudget,
      DriverProfile.agriculturalForestry => baselineFrameBudget,
      DriverProfile.noviceUrban => const Duration(microseconds: 18000),
      DriverProfile.ageingRural => const Duration(microseconds: 22000),
      DriverProfile.foreignTouristSnowZone =>
        const Duration(microseconds: 22000),
    };

    // Caution-add-only invariant: per-cohort budget MUST be >= baseline
    // (= MORE LENIENT = MORE caution toward visual-cognitive-margin).
    assert(
      budget.inMicroseconds >= baselineFrameBudget.inMicroseconds,
      'PerformanceBudgetConfig.forProfile($profile) returned '
      '$budget which is tighter than baseline '
      '$baselineFrameBudget; caution-add-only invariant violated.',
    );

    return PerformanceBudgetConfig(frameBudget: budget);
  }

  @override
  List<Object?> get props => [frameBudget, warningRatio, sustainedFrames];
}

/// Integrator-supplied source of `FrameTiming` events.
///
/// Mirrors the `GlanceEventSource` / `VehicleClassProvider` pattern
/// (the package supplies the interface; the integrator supplies the
/// implementation). Typical Flutter implementations adapt
/// `SchedulerBinding.instance.addTimingsCallback` into a broadcast
/// stream the tracker subscribes to.
abstract class FrameTimingProvider {
  /// Broadcast stream of `FrameTiming` events from the integrator's
  /// rendering sub-system.
  Stream<FrameTiming> get frameTimings;
}

/// Sealed event type emitted on the [PerformanceBudget.budgetEvents]
/// stream. Integrators pattern-match on `BudgetWarning` /
/// `BudgetExhausted`.
sealed class PerformanceBudgetEvent extends Equatable {
  const PerformanceBudgetEvent();
}

/// Emitted once when the most-recent frame's total time crosses the
/// warning ratio (default 75% of frameBudget consumed). Carries the
/// `consumed` and `remaining` durations at the moment of the warning.
class BudgetWarning extends PerformanceBudgetEvent {
  /// Frame total time as observed.
  final Duration consumed;

  /// Remaining headroom against frameBudget; clamped to zero.
  final Duration remaining;

  const BudgetWarning({required this.consumed, required this.remaining});

  @override
  List<Object?> get props => [consumed, remaining];
}

/// Emitted once after `sustainedFrames` consecutive over-budget frames.
/// Carries the over-budget `consumed` (most-recent over-budget frame)
/// and `overshoot` (amount past frameBudget; never negative).
class BudgetExhausted extends PerformanceBudgetEvent {
  final Duration consumed;
  final Duration overshoot;

  const BudgetExhausted({required this.consumed, required this.overshoot});

  @override
  List<Object?> get props => [consumed, overshoot];
}

/// Stateful tracker for the per-frame render-time budget.
///
/// See library-level documentation for invariants (caution-add-only /
/// severity-not-profile / driver-always-drives) and wiring example.
class PerformanceBudget {
  PerformanceBudget({
    PerformanceBudgetConfig config = const PerformanceBudgetConfig(),
  })  : _config = config,
        _consecutiveOverBudget = 0,
        _warningFired = false,
        _exhaustedFired = false;

  final PerformanceBudgetConfig _config;
  final StreamController<PerformanceBudgetEvent> _controller =
      StreamController<PerformanceBudgetEvent>.broadcast();

  Duration _lastFrameTotal = Duration.zero;
  int _consecutiveOverBudget;
  bool _warningFired;
  bool _exhaustedFired;
  bool _disposed = false;

  /// Active configuration (per-frame budget + ratios).
  PerformanceBudgetConfig get config => _config;

  /// Most-recent observed total frame time (build + raster).
  Duration get lastFrameTotal => _lastFrameTotal;

  /// Snapshot of current consumption + remaining budget against the
  /// most-recent frame. Useful for integrator logging / dashboards.
  ({Duration consumed, Duration remaining}) get budgetSnapshot {
    final remainingMicros = _config.frameBudget.inMicroseconds -
        _lastFrameTotal.inMicroseconds;
    final remaining = remainingMicros < 0
        ? Duration.zero
        : Duration(microseconds: remainingMicros);
    return (consumed: _lastFrameTotal, remaining: remaining);
  }

  /// Broadcast stream of `BudgetWarning` / `BudgetExhausted` events.
  /// Each event class fires at most once per active budget cycle; a
  /// fresh cycle begins after [reset].
  Stream<PerformanceBudgetEvent> get budgetEvents => _controller.stream;

  /// Record a `FrameTiming` against the budget.
  ///
  /// **Caution-add-only**: this method observes per-frame total time;
  /// it never relaxes the budget. The budget itself is set at
  /// construction and only [reset] resets the warning/exhausted
  /// fired-once flags.
  void record(FrameTiming timing) {
    if (_disposed) return;

    // FrameTiming.totalSpan is build + raster + UI thread latency for
    // the frame. We observe the total per Skia 60fps reference.
    final total = timing.totalSpan;

    assert(
      total >= Duration.zero,
      'FrameTiming.totalSpan must be non-negative '
      '(got $total); caution-add-only invariant violated.',
    );

    _lastFrameTotal = total;

    final consumedRatio =
        total.inMicroseconds / _config.frameBudget.inMicroseconds;

    if (!_warningFired && consumedRatio >= _config.warningRatio) {
      _warningFired = true;
      _controller.add(BudgetWarning(
        consumed: total,
        remaining: budgetSnapshot.remaining,
      ));
    }

    if (consumedRatio >= 1.0) {
      _consecutiveOverBudget += 1;
      if (!_exhaustedFired &&
          _consecutiveOverBudget >= _config.sustainedFrames) {
        _exhaustedFired = true;
        final overshootMicros =
            total.inMicroseconds - _config.frameBudget.inMicroseconds;
        _controller.add(BudgetExhausted(
          consumed: total,
          overshoot: Duration(
            microseconds: overshootMicros < 0 ? 0 : overshootMicros,
          ),
        ));
      }
    } else {
      _consecutiveOverBudget = 0;
    }
  }

  /// Reset the budget for a new cycle (typically render-pipeline
  /// reconfiguration / explicit reset). Integrator owns the cycle
  /// boundary; the tracker does NOT auto-reset.
  void reset(BudgetResetReason reason) {
    if (_disposed) return;
    _lastFrameTotal = Duration.zero;
    _consecutiveOverBudget = 0;
    _warningFired = false;
    _exhaustedFired = false;
  }

  /// Release the broadcast stream. Idempotent; safe to call multiple
  /// times (subsequent calls are no-ops).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }
}
