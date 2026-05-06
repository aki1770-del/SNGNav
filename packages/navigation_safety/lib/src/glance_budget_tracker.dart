/// Off-road-glance budget tracker for advisory cognitive-load management.
///
/// Why this exists (literature anchor):
///
/// NHTSA Phase 2 Driver Distraction Guidelines (NHTSA-2010-0053; widely
/// cited operational anchor) describe a 12-second total off-road glance
/// budget for any single driver task — the cumulative time the driver's
/// eyes may leave the forward roadway across a sequence of glances
/// before the task is judged distraction-class. This tracker exposes
/// the budget at the integrator-package boundary so apps can render a
/// budget indicator, modulate voice-guidance pace, or escalate
/// advisories as the budget approaches exhaustion.
///
/// **Advisory not control.** The tracker emits `BudgetWarning` and
/// `BudgetExhausted` records on a broadcast stream the integrator may
/// subscribe to. The package mounts no actuator, no automatic input
/// suppression, no driver lockout. The driver always drives; the
/// tracker only reports.
///
/// **Caution-add-only invariant** (load-bearing): once recorded, a
/// glance event consumes budget irreversibly within a single trip.
/// `record()` only DECREASES (or holds) `remainingBudget`; it never
/// INCREASES it. Trip-class boundary detection (parking-detected /
/// long-pause-detected / explicit-trip-end) is integrator-owned via
/// [reset]. Auto-relax-on-cooldown is intentionally absent at v1; an
/// auto-relax pattern can graduate in v2 when field-evidence
/// distinguishes legitimate cooldown from "driver is masking budget
/// exhaustion".
///
/// **Severity-not-profile invariant**: the budget tracker is timing-
/// class only. It adjusts when alerts fire (via integrator listening
/// to `budgetEvents`) — never severity. Critical alerts in
/// `navigation_safety` retain their critical-bypass invariant
/// regardless of glance-budget state.
///
/// **Driver-always-drives invariant**: the tracker is presentation-
/// class only. The integrator may dim a non-essential UI element when
/// `BudgetWarning` fires, but the package itself does not modify any
/// driver-facing surface or vehicle state.
///
/// **Driver-facing loom**: the driver receives an indication when
/// cumulative off-road glance time approaches the published NHTSA
/// budget so attention can return to the road before the budget is
/// exhausted. The driver-experience surface for the warning belongs
/// to the integrator HMI; this package supplies the substrate.
///
/// Typical wiring:
///
/// ```dart
/// final tracker = GlanceBudgetTracker();
/// tracker.budgetEvents.listen((event) {
///   if (event is BudgetWarning) {
///     // integrator-class HMI: dim non-essential card, soften voice
///   } else if (event is BudgetExhausted) {
///     // integrator-class HMI: simplify display, lengthen alert dwell
///   }
/// });
///
/// // From a glance-detection sub-system the integrator owns:
/// tracker.record(GlanceEvent(
///   timestamp: DateTime.now(),
///   duration: Duration(milliseconds: 800),
///   modalClass: GlanceModalClass.visual,
/// ));
/// ```
library;

import 'dart:async';

import 'package:equatable/equatable.dart';

/// Modal class of an off-road glance event.
///
/// Informational at v1: the budget pool is shared across modal classes
/// per the NHTSA Phase 2 12-second total. Per-modal-class sub-budgets
/// can graduate in v2 when field evidence supports differentiation.
enum GlanceModalClass {
  /// Glance away from the road for visual task (e.g. reading a label
  /// on a non-essential UI element).
  visual,

  /// Cognitively distracting interaction without a glance away (e.g.
  /// a complex hands-free voice exchange that competes for attention).
  cognitive,

  /// Manual interaction (e.g. reaching to a touchscreen control); often
  /// co-occurs with `visual` but recorded separately when an integrator
  /// can distinguish.
  manual,
}

/// Reason a budget reset was requested by the integrator.
///
/// Reset is integrator-owned at v1 (caution-add-only — never auto-
/// relax). The reason field is informational and may be used by the
/// integrator's own analytics.
enum BudgetResetReason {
  /// New trip began (parking-detected / re-ignition / explicit start).
  tripStart,

  /// Trip ended (parking-detected / explicit stop).
  tripEnd,

  /// Long pause detected (e.g. driver stopped for an extended period
  /// at a rest area / charging station).
  longPause,

  /// Integrator explicitly requested reset (e.g. user-initiated).
  explicit,
}

/// Configuration for the NHTSA-anchored 12-second off-road glance
/// budget. Per-modal-class tunable; default 4s + 4s + 4s = 12s total.
///
/// **Anchor**: NHTSA Phase 2 Driver Distraction Guidelines (12-second
/// total off-road glance budget). The 12-second total is published-
/// anchor; the equal 4-4-4 modal-class split is a design-default
/// (UNVERIFIED-magnitude pending field-evidence on whether visual /
/// cognitive / manual sub-budgets warrant differentiation).
class NHTSAGlanceBudgetConfig extends Equatable {
  /// Total off-road glance budget per task. Default 12 seconds per
  /// NHTSA Phase 2.
  final Duration totalBudget;

  /// Per-modal-class sub-budget. At v1 the tracker pools all events
  /// against [totalBudget] regardless of modal class; the per-modal
  /// values are informational and reserved for v2 differentiation.
  final Map<GlanceModalClass, Duration> perModalBudget;

  /// Threshold ratio at which `BudgetWarning` fires. Default 0.75
  /// (warning when 75% of the budget has been consumed = 25% remains).
  final double warningRatio;

  const NHTSAGlanceBudgetConfig({
    this.totalBudget = const Duration(seconds: 12),
    this.perModalBudget = const {
      GlanceModalClass.visual: Duration(seconds: 4),
      GlanceModalClass.cognitive: Duration(seconds: 4),
      GlanceModalClass.manual: Duration(seconds: 4),
    },
    this.warningRatio = 0.75,
  })  : assert(warningRatio > 0.0 && warningRatio < 1.0,
            'warningRatio must be in (0.0, 1.0)');

  @override
  List<Object?> get props => [totalBudget, perModalBudget, warningRatio];
}

/// A single off-road glance / cognitively-distracting event.
///
/// Integrator constructs `GlanceEvent` instances from whatever glance-
/// detection sub-system they own (eye-tracker / camera / touch-event
/// proxy / voice-engagement timer). The package does not invent glance
/// events; it only consumes them.
class GlanceEvent extends Equatable {
  /// Wall-clock timestamp at which the glance event began.
  final DateTime timestamp;

  /// Duration of the glance event (must be non-negative).
  final Duration duration;

  /// Modal class of the glance event.
  final GlanceModalClass modalClass;

  const GlanceEvent({
    required this.timestamp,
    required this.duration,
    required this.modalClass,
  });

  @override
  List<Object?> get props => [timestamp, duration, modalClass];
}

/// Sealed event type emitted on the [GlanceBudgetTracker.budgetEvents]
/// stream. Integrators pattern-match on `BudgetWarning` / `BudgetExhausted`.
sealed class GlanceBudgetEvent extends Equatable {
  const GlanceBudgetEvent();
}

/// Emitted once when the budget crosses the warning ratio (default 75%
/// consumed). Carries the `consumed` and `remaining` durations at the
/// moment of the warning.
class BudgetWarning extends GlanceBudgetEvent {
  final Duration consumed;
  final Duration remaining;

  const BudgetWarning({required this.consumed, required this.remaining});

  @override
  List<Object?> get props => [consumed, remaining];
}

/// Emitted once when the budget reaches or passes 100% consumed
/// (zero or negative remaining). Carries the `consumed` and `overshoot`
/// durations (overshoot is the amount past `totalBudget`, never
/// negative).
class BudgetExhausted extends GlanceBudgetEvent {
  final Duration consumed;
  final Duration overshoot;

  const BudgetExhausted({required this.consumed, required this.overshoot});

  @override
  List<Object?> get props => [consumed, overshoot];
}

/// Integrator-supplied source of glance events.
///
/// Mirrors the `VehicleClassProvider` pattern (the package supplies the
/// interface; the integrator supplies the implementation). The package
/// does not invent glance events; the integrator's eye-tracker /
/// camera / proxy detector emits them.
abstract class GlanceEventSource {
  /// Stream of glance events from the integrator's detection sub-system.
  Stream<GlanceEvent> get glanceEvents;
}

/// Stateful tracker for the NHTSA-anchored off-road glance budget.
///
/// See library-level documentation for invariants (caution-add-only /
/// severity-not-profile / driver-always-drives) and wiring example.
class GlanceBudgetTracker {
  GlanceBudgetTracker({
    NHTSAGlanceBudgetConfig config = const NHTSAGlanceBudgetConfig(),
  })  : _config = config,
        _consumed = Duration.zero,
        _warningFired = false,
        _exhaustedFired = false;

  final NHTSAGlanceBudgetConfig _config;
  final StreamController<GlanceBudgetEvent> _controller =
      StreamController<GlanceBudgetEvent>.broadcast();

  Duration _consumed;
  bool _warningFired;
  bool _exhaustedFired;
  bool _disposed = false;

  /// Total budget per the active config.
  Duration get totalBudget => _config.totalBudget;

  /// Cumulative glance duration recorded against the budget since the
  /// last [reset] (or construction).
  Duration get consumed => _consumed;

  /// Remaining budget. Clamped to zero (never negative); use
  /// `BudgetExhausted.overshoot` to read past-budget magnitude.
  Duration get remainingBudget {
    final remainingMicros =
        _config.totalBudget.inMicroseconds - _consumed.inMicroseconds;
    if (remainingMicros < 0) return Duration.zero;
    return Duration(microseconds: remainingMicros);
  }

  /// Broadcast stream of `BudgetWarning` / `BudgetExhausted` events.
  /// Each event class fires at most once per active budget cycle; a
  /// fresh cycle begins after [reset].
  Stream<GlanceBudgetEvent> get budgetEvents => _controller.stream;

  /// Record a glance event against the budget.
  ///
  /// **Caution-add-only**: this method only DECREASES `remainingBudget`
  /// (or holds it constant for zero-duration events). A debug-mode
  /// runtime assert verifies the non-increase invariant; in release
  /// builds the assert is elided per Dart `assert` semantics.
  void record(GlanceEvent event) {
    if (_disposed) return;
    assert(
      event.duration >= Duration.zero,
      'GlanceEvent.duration must be non-negative '
      '(got ${event.duration}); caution-add-only invariant violated.',
    );

    final priorConsumed = _consumed;
    _consumed = Duration(
      microseconds: _consumed.inMicroseconds + event.duration.inMicroseconds,
    );

    // Defensive non-decrease check (mirror precedent: vehicle_threshold_
    // overrides.dart applyOverrideForToken). The semantic invariant is
    // that consumed-budget never decreases between record() calls; this
    // assert documents the invariant explicitly so a future change
    // that regresses the invariant fails loudly in tests.
    assert(
      _consumed.inMicroseconds >= priorConsumed.inMicroseconds,
      'GlanceBudgetTracker.consumed decreased after record() '
      '($priorConsumed -> $_consumed); caution-add-only invariant violated.',
    );

    final consumedRatio =
        _consumed.inMicroseconds / _config.totalBudget.inMicroseconds;

    if (!_warningFired && consumedRatio >= _config.warningRatio) {
      _warningFired = true;
      _controller.add(BudgetWarning(
        consumed: _consumed,
        remaining: remainingBudget,
      ));
    }

    if (!_exhaustedFired && consumedRatio >= 1.0) {
      _exhaustedFired = true;
      final overshootMicros =
          _consumed.inMicroseconds - _config.totalBudget.inMicroseconds;
      _controller.add(BudgetExhausted(
        consumed: _consumed,
        overshoot: Duration(microseconds: overshootMicros),
      ));
    }
  }

  /// Reset the budget for a new cycle (typically trip-start / trip-end /
  /// long-pause / explicit reset). Integrator owns the trip-class
  /// boundary; the tracker does NOT auto-reset.
  ///
  /// Note: reset is the only operation that increases `remainingBudget`,
  /// and it does so by integrator-explicit request — preserving the
  /// caution-add-only invariant within a trip while permitting the
  /// integrator to begin a fresh trip cycle.
  void reset(BudgetResetReason reason) {
    if (_disposed) return;
    _consumed = Duration.zero;
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
