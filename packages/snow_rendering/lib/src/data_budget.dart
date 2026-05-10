/// Data-fetch budget tracker for snow-overlay render bandwidth
/// management.
///
/// Why this exists:
///
/// Snow-overlay rendering pulls supplemental data (high-density tile
/// detail / per-segment surface state / per-frame particle parameter
/// updates) over network bandwidth that competes with the rest of the
/// driver-protection HMI. When per-cycle data fetch sustains over the
/// per-cohort budget, the integrator HMI loses bandwidth headroom for
/// safety-critical fetches (route alert / road-closure / weather-
/// condition refresh). This tracker exposes the per-cycle data
/// consumption against a per-cohort budget so the integrator can drop
/// fidelity (request lower-resolution overlays / defer non-essential
/// updates) before the budget is exhausted.
///
/// **Advisory not control.** The tracker emits `BudgetWarning`,
/// `BudgetExhausted`, and `RenderFidelityDrop` records on a broadcast
/// stream the integrator may subscribe to. The package mounts no
/// actuator, no automatic input suppression, no driver lockout. The
/// driver always drives; the tracker only reports.
///
/// **Caution-add-only invariant** (load-bearing): the budget can only
/// AUTO-TIGHTEN within a render cycle (= toward LESS data = toward
/// fidelity-drop = toward MORE caution). Auto-relax (loosening) is
/// FORBIDDEN automatically; relaxing the budget within a cycle requires
/// an integrator-supplied [BudgetRelaxConfirmation] confirmation token,
/// mirroring the cap-override-with-confirmation pattern from
/// `navigation_safety_core` 0.10.0 #30.
///
/// **Severity-not-profile invariant**: the budget tracker is bandwidth-
/// class only. It adjusts when the integrator HMI drops fidelity; it
/// does NOT adjust alert severity, score floors, or critical
/// thresholds. Critical alerts in `navigation_safety` retain their
/// critical-bypass invariant regardless of data-budget state.
///
/// **Driver-always-drives invariant**: the tracker is presentation-
/// class only. The integrator may render lower-fidelity snow overlay
/// when `BudgetWarning` fires, but the package itself does not modify
/// any driver-facing surface or vehicle state.
///
/// **Per-cohort budget defaults** (UNVERIFIED-magnitude design-default-
/// hypothesis pending field-measurement validation):
///
/// - `professional`, `snowZoneExperienced`, `agriculturalForestry` →
///   4MB / cycle (mobile-bandwidth-respectful baseline).
/// - `noviceUrban` → 3MB (urban-mobile-data-cost margin).
/// - `ageingRural` → 2MB (rural-bandwidth-margin; assumed slower data;
///   tighter budget reduces fetch wait).
/// - `foreignTouristSnowZone` → 2MB (international-roaming-cost
///   margin).
///
/// All per-cohort values are SMALLER OR EQUAL to 4MB baseline (= LESS
/// data = MORE caution-add toward fidelity-drop). Values larger than
/// the baseline are caught by the runtime assert.
///
/// Typical wiring:
///
/// ```dart
/// final tracker = DataBudget(
///   config: DataBudgetConfig.forProfile(DriverProfile.ageingRural),
/// );
/// tracker.budgetEvents.listen((event) {
///   if (event is BudgetWarning) {
///     // integrator-class HMI: defer non-essential fetch
///   } else if (event is BudgetExhausted) {
///     // integrator-class HMI: drop fidelity
///   }
/// });
///
/// // From the integrator's network sub-system:
/// tracker.record(DataFetchEvent(
///   timestamp: DateTime.now(),
///   bytesFetched: 524288, // 512 KB
/// ));
/// ```
library;

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Reason a budget reset was requested by the integrator.
///
/// Reset is integrator-owned at v1 (caution-add-only — never auto-
/// relax). The reason field is informational and may be used by the
/// integrator's own analytics.
enum BudgetResetReason {
  /// Render cycle started (e.g. new tile region entered).
  renderCycleStart,

  /// Render cycle ended.
  renderCycleEnd,

  /// Network condition changed materially (e.g. WiFi → mobile-data
  /// transition; integrator-detected).
  networkClassChange,

  /// Integrator explicitly requested reset (e.g. user-initiated).
  explicit,
}

/// Configuration for the per-render-cycle data-fetch budget.
///
/// **Anchor**: typical mobile-data-respect range 2-8MB / minute for
/// supplemental overlay fetch. The 4MB baseline is engineering
/// judgement consistent with mobile-bandwidth-respect; the per-cohort
/// tighter-direction defaults are design-default hypotheses pending
/// field-measurement validation (per-cohort bandwidth-class not yet
/// anchored in a published study mapping driver-class to optimal-data-
/// budget specifically).
class DataBudgetConfig extends Equatable {
  /// Total data budget per render cycle. Default 4MB (4_194_304 bytes).
  final int budgetBytes;

  /// Threshold ratio at which `BudgetWarning` fires. Default 0.75
  /// (warning when 75% of the budget has been consumed = 25% remains).
  final double warningRatio;

  /// Baseline budget against which per-cohort budgets are compared in
  /// the caution-add-only invariant. Equal to 4MB.
  static const int baselineBudgetBytes = 4 * 1024 * 1024;

  const DataBudgetConfig({
    this.budgetBytes = baselineBudgetBytes,
    this.warningRatio = 0.75,
  }) : assert(budgetBytes > 0, 'budgetBytes must be > 0'),
       assert(
         warningRatio > 0.0 && warningRatio < 1.0,
         'warningRatio must be in (0.0, 1.0)',
       );

  /// Per-cohort tighter-direction defaults.
  ///
  /// **Caution-add-only invariant**: every returned config has a
  /// `budgetBytes` `<=` 4MB baseline. Larger-than-baseline values
  /// would relax the bandwidth-margin direction and are rejected at
  /// runtime via debug-mode assertion.
  ///
  /// Magnitudes are UNVERIFIED-magnitude design-default-hypothesis
  /// (see library doc). Per-population calibration deferred pending
  /// fleet-class field measurement.
  factory DataBudgetConfig.forProfile(DriverProfile profile) {
    final budget = switch (profile) {
      DriverProfile.professional => baselineBudgetBytes,
      DriverProfile.snowZoneExperienced => baselineBudgetBytes,
      DriverProfile.agriculturalForestry => baselineBudgetBytes,
      DriverProfile.noviceUrban => 3 * 1024 * 1024,
      DriverProfile.ageingRural => 2 * 1024 * 1024,
      DriverProfile.foreignTouristSnowZone => 2 * 1024 * 1024,
    };

    // Caution-add-only invariant: per-cohort budget MUST be <= baseline
    // (= LESS data = MORE caution-add toward fidelity-drop).
    assert(
      budget <= baselineBudgetBytes,
      'DataBudgetConfig.forProfile($profile) returned '
      '$budget bytes which is larger than baseline '
      '$baselineBudgetBytes; caution-add-only invariant violated.',
    );

    return DataBudgetConfig(budgetBytes: budget);
  }

  @override
  List<Object?> get props => [budgetBytes, warningRatio];
}

/// A single data-fetch event observed by the integrator's network sub-
/// system.
class DataFetchEvent extends Equatable {
  /// Wall-clock timestamp at which the fetch completed.
  final DateTime timestamp;

  /// Bytes fetched (must be non-negative).
  final int bytesFetched;

  const DataFetchEvent({required this.timestamp, required this.bytesFetched});

  @override
  List<Object?> get props => [timestamp, bytesFetched];
}

/// Integrator-supplied source of `DataFetchEvent`s.
///
/// Mirrors the `FrameTimingProvider` / `GlanceEventSource` pattern (the
/// package supplies the interface; the integrator supplies the
/// implementation).
abstract class DataMeterProvider {
  /// Broadcast stream of `DataFetchEvent`s from the integrator's
  /// network sub-system.
  Stream<DataFetchEvent> get dataFetchEvents;
}

/// Confirmation token required to relax (loosen) the data budget
/// within an active render cycle.
///
/// **Driver-always-drives invariant** (load-bearing): auto-relax is
/// FORBIDDEN within a cycle; only an integrator-supplied confirmation
/// token may loosen the budget. The token must be constructed by the
/// integrator with affirmative reasoning (the integrator confirms
/// network-condition improved, user requested high-fidelity, etc.); a
/// default-constructed token is rejected at runtime via debug-mode
/// assertion. Mirrors the cap-override-with-confirmation pattern from
/// `navigation_safety_core` 0.10.0 #30.
class BudgetRelaxConfirmation {
  /// Reason the integrator is loosening the budget. Required; empty
  /// string is rejected at runtime.
  final String reason;

  /// Wall-clock timestamp at which the integrator confirmed the relax.
  final DateTime confirmedAt;

  /// `true` when the integrator has affirmatively confirmed the relax
  /// at the integrator's own decision surface (e.g. user-tapped
  /// confirm). `false` is rejected at runtime via debug-mode assertion.
  final bool isConfirmed;

  const BudgetRelaxConfirmation({
    required this.reason,
    required this.confirmedAt,
    required this.isConfirmed,
  });
}

/// Sealed event type emitted on the [DataBudget.budgetEvents] stream.
sealed class DataBudgetEvent extends Equatable {
  const DataBudgetEvent();
}

/// Emitted once when consumed bytes cross the warning ratio (default
/// 75% of `budgetBytes` consumed).
class BudgetWarning extends DataBudgetEvent {
  final int consumedBytes;
  final int remainingBytes;

  const BudgetWarning({
    required this.consumedBytes,
    required this.remainingBytes,
  });

  @override
  List<Object?> get props => [consumedBytes, remainingBytes];
}

/// Emitted once when consumed bytes reach or pass 100% of `budgetBytes`.
class BudgetExhausted extends DataBudgetEvent {
  final int consumedBytes;
  final int overshootBytes;

  const BudgetExhausted({
    required this.consumedBytes,
    required this.overshootBytes,
  });

  @override
  List<Object?> get props => [consumedBytes, overshootBytes];
}

/// Emitted when the integrator HMI should drop snow-overlay render
/// fidelity. Today emitted in lock-step with `BudgetExhausted`; a
/// future revision may emit independently from a tighter heuristic.
class RenderFidelityDrop extends DataBudgetEvent {
  final int consumedBytes;
  final int budgetBytes;

  const RenderFidelityDrop({
    required this.consumedBytes,
    required this.budgetBytes,
  });

  @override
  List<Object?> get props => [consumedBytes, budgetBytes];
}

/// Stateful tracker for the per-render-cycle data-fetch budget.
///
/// See library-level documentation for invariants (caution-add-only /
/// severity-not-profile / driver-always-drives) and wiring example.
class DataBudget {
  DataBudget({DataBudgetConfig config = const DataBudgetConfig()})
    : _config = config,
      _consumedBytes = 0,
      _warningFired = false,
      _exhaustedFired = false;

  DataBudgetConfig _config;
  final StreamController<DataBudgetEvent> _controller =
      StreamController<DataBudgetEvent>.broadcast();

  int _consumedBytes;
  bool _warningFired;
  bool _exhaustedFired;
  bool _disposed = false;

  /// Active configuration (budget + ratio).
  DataBudgetConfig get config => _config;

  /// Cumulative bytes recorded against the budget since the last
  /// [reset] (or construction).
  int get consumedBytes => _consumedBytes;

  /// Remaining budget. Clamped to zero (never negative).
  int get remainingBytes {
    final remaining = _config.budgetBytes - _consumedBytes;
    return remaining < 0 ? 0 : remaining;
  }

  /// Snapshot of current consumption + remaining budget. Useful for
  /// integrator logging / dashboards.
  ({int consumedBytes, int remainingBytes}) get budgetSnapshot {
    return (consumedBytes: _consumedBytes, remainingBytes: remainingBytes);
  }

  /// Broadcast stream of budget events.
  Stream<DataBudgetEvent> get budgetEvents => _controller.stream;

  /// Record a data-fetch event against the budget.
  ///
  /// **Caution-add-only**: this method only INCREASES `consumedBytes`
  /// (or holds it for zero-byte events); it never decreases. A
  /// debug-mode runtime assert verifies the non-decrease invariant.
  void record(DataFetchEvent event) {
    if (_disposed) return;
    assert(
      event.bytesFetched >= 0,
      'DataFetchEvent.bytesFetched must be non-negative '
      '(got ${event.bytesFetched}); caution-add-only invariant violated.',
    );

    final priorConsumed = _consumedBytes;
    _consumedBytes = _consumedBytes + event.bytesFetched;

    assert(
      _consumedBytes >= priorConsumed,
      'DataBudget.consumedBytes decreased after record() '
      '($priorConsumed -> $_consumedBytes); caution-add-only invariant '
      'violated.',
    );

    final consumedRatio = _consumedBytes / _config.budgetBytes;

    if (!_warningFired && consumedRatio >= _config.warningRatio) {
      _warningFired = true;
      _controller.add(
        BudgetWarning(
          consumedBytes: _consumedBytes,
          remainingBytes: remainingBytes,
        ),
      );
    }

    if (!_exhaustedFired && consumedRatio >= 1.0) {
      _exhaustedFired = true;
      final overshoot = _consumedBytes - _config.budgetBytes;
      _controller.add(
        BudgetExhausted(
          consumedBytes: _consumedBytes,
          overshootBytes: overshoot < 0 ? 0 : overshoot,
        ),
      );
      _controller.add(
        RenderFidelityDrop(
          consumedBytes: _consumedBytes,
          budgetBytes: _config.budgetBytes,
        ),
      );
    }
  }

  /// Auto-tighten the budget to a smaller value within an active cycle.
  ///
  /// **Caution-add-only**: the new budget must be `<=` the active
  /// budget (= toward LESS data = toward fidelity-drop = toward MORE
  /// caution). Calling with a larger budget is rejected at runtime via
  /// debug-mode assertion. Use [relax] (with confirmation token) for
  /// integrator-affirmed loosening.
  void tighten(int newBudgetBytes) {
    if (_disposed) return;
    assert(newBudgetBytes > 0, 'DataBudget.tighten newBudgetBytes must be > 0');
    assert(
      newBudgetBytes <= _config.budgetBytes,
      'DataBudget.tighten newBudgetBytes ($newBudgetBytes) must be <= '
      'active budgetBytes (${_config.budgetBytes}); caution-add-only '
      'invariant violated.',
    );
    _config = DataBudgetConfig(
      budgetBytes: newBudgetBytes,
      warningRatio: _config.warningRatio,
    );
  }

  /// Relax (loosen) the budget within an active cycle. Requires an
  /// integrator-supplied affirmative confirmation token.
  ///
  /// **Driver-always-drives invariant**: this method REJECTS any
  /// confirmation that is not affirmative at runtime via debug-mode
  /// assertion. The integrator MUST construct the token with
  /// `isConfirmed: true` and a non-empty `reason`.
  void relax(int newBudgetBytes, BudgetRelaxConfirmation confirmation) {
    if (_disposed) return;
    assert(
      confirmation.isConfirmed,
      'DataBudget.relax requires confirmation.isConfirmed == true; '
      'driver-always-drives invariant: auto-relax forbidden.',
    );
    assert(
      confirmation.reason.isNotEmpty,
      'DataBudget.relax requires non-empty confirmation.reason; '
      'driver-always-drives invariant: blank-relax forbidden.',
    );
    assert(newBudgetBytes > 0, 'DataBudget.relax newBudgetBytes must be > 0');
    _config = DataBudgetConfig(
      budgetBytes: newBudgetBytes,
      warningRatio: _config.warningRatio,
    );
  }

  /// Reset the budget for a new render cycle. Integrator owns the
  /// cycle boundary; the tracker does NOT auto-reset.
  void reset(BudgetResetReason reason) {
    if (_disposed) return;
    _consumedBytes = 0;
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
