/// Viewport-class render-budget bloc — composes performance + data
/// budget streams into a single render-fidelity recommendation.
///
/// Why this exists:
///
/// `offline_tiles` 0.5.0 ships `PerformanceBudget` (per-frame render
/// time tracking) and `snow_rendering` 0.2.0 ships `DataBudget`
/// (per-cycle bandwidth tracking). Each emits warnings independently;
/// a typical integrator HMI consumes BOTH (frame-budget exhaustion
/// changes layer fidelity at the render layer; data-budget exhaustion
/// changes fetch fidelity at the network layer). This bloc composes
/// the two streams into a single `ViewportRenderState` with a
/// `RenderFidelity` recommendation so the integrator does not have to
/// invent the composition rule.
///
/// **Caution-add-direction-wins on conflict** (load-bearing): when
/// PerformanceBudget and DataBudget disagree on direction, the
/// caution-add direction wins. Concretely:
///
/// - Either budget emits `BudgetExhausted` → fidelity drops to LOW.
/// - Either budget emits `BudgetWarning` (and neither is exhausted) →
///   fidelity drops to MEDIUM.
/// - Both budgets are normal → fidelity is HIGH.
///
/// The bloc never RAISES fidelity in response to a stream event; once
/// dropped, fidelity returns to HIGH only after [reset] or an explicit
/// [ViewportBudgetReset] event. Mirrors the auto-relax-forbidden
/// pattern in `DataBudget.relax`.
///
/// **Per-cohort `RenderFidelityFloor`** (UNVERIFIED-magnitude design-
/// default-hypothesis pending field-measurement validation): each
/// cohort defines the LOWEST fidelity the bloc will recommend for that
/// cohort. Cohorts whose visual-cognitive-margin demands a richer
/// rendering (`ageingRural`, `foreignTouristSnowZone`) have a HIGHER
/// floor (= bloc never drops below MEDIUM); cohorts who can tolerate
/// the lowest fidelity have the LOW floor.
///
/// - `ageingRural`, `foreignTouristSnowZone` → MEDIUM floor (never
///   drops to LOW; visual-cognitive-margin demands richer rendering
///   even under budget pressure).
/// - `noviceUrban` → MEDIUM floor (same rationale; experience-class).
/// - `professional`, `snowZoneExperienced`, `agriculturalForestry` →
///   LOW floor (experienced cohorts; can tolerate fidelity drop).
///
/// **Severity-not-profile invariant**: the bloc modulates RENDER
/// fidelity only. It does NOT modify alert severity, score floors, or
/// critical thresholds. Critical alerts in `navigation_safety` retain
/// their critical-bypass invariant regardless of viewport-render
/// state.
///
/// **Driver-always-drives invariant**: the bloc emits state for the
/// integrator HMI to render. It mounts no actuator; the driver
/// always drives.
///
/// Typical wiring:
///
/// ```dart
/// final perfBudget = PerformanceBudget(
///   config: PerformanceBudgetConfig.forProfile(profile),
/// );
/// final dataBudget = DataBudget(
///   config: DataBudgetConfig.forProfile(profile),
/// );
/// final bloc = ViewportRenderBudgetBloc(
///   config: ViewportRenderConfig.forProfile(profile),
/// );
/// bloc.attachPerformanceBudgetStream(perfBudget.budgetEvents);
/// bloc.attachDataBudgetStream(dataBudget.budgetEvents);
/// // Listen to bloc.stream for ViewportRenderState transitions.
/// ```
library;

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Recommended render fidelity for the integrator HMI.
enum RenderFidelity {
  /// Full fidelity (all layers visible at design quality). Default.
  high,

  /// Reduced fidelity (drop non-essential layers / soften animation).
  medium,

  /// Minimum fidelity (only safety-critical layers; minimal animation).
  low,
}

/// Lowest fidelity the bloc will recommend for a given cohort.
enum RenderFidelityFloor {
  /// Bloc may drop fidelity all the way to LOW.
  low,

  /// Bloc never drops below MEDIUM (visual-cognitive-margin cohorts).
  medium,
}

/// Configuration for the viewport-class render budget composition.
///
/// **Anchor**: per-cohort floors are UNVERIFIED-magnitude design-
/// default-hypothesis (see library doc). API shape is intentional and
/// stable; magnitudes deferred pending fleet-class field measurement.
class ViewportRenderConfig extends Equatable {
  /// Lowest fidelity the bloc will recommend for the active cohort.
  final RenderFidelityFloor floor;

  const ViewportRenderConfig({
    this.floor = RenderFidelityFloor.low,
  });

  /// Per-cohort floor defaults (UNVERIFIED-magnitude design-default-
  /// hypothesis; see library doc).
  factory ViewportRenderConfig.forProfile(DriverProfile profile) {
    final floor = switch (profile) {
      DriverProfile.professional => RenderFidelityFloor.low,
      DriverProfile.snowZoneExperienced => RenderFidelityFloor.low,
      DriverProfile.agriculturalForestry => RenderFidelityFloor.low,
      DriverProfile.noviceUrban => RenderFidelityFloor.medium,
      DriverProfile.ageingRural => RenderFidelityFloor.medium,
      DriverProfile.foreignTouristSnowZone => RenderFidelityFloor.medium,
    };
    return ViewportRenderConfig(floor: floor);
  }

  @override
  List<Object?> get props => [floor];
}

/// Sealed event hierarchy consumed by [ViewportRenderBudgetBloc].
sealed class ViewportRenderBudgetEvent extends Equatable {
  const ViewportRenderBudgetEvent();
  @override
  List<Object?> get props => const [];
}

/// Internal event injected when a `BudgetWarning` arrives on either
/// stream. Public: integrators may also dispatch directly when
/// composing additional budget sources.
class ViewportPerformanceBudgetWarning extends ViewportRenderBudgetEvent {
  const ViewportPerformanceBudgetWarning();
}

/// Internal event injected when a `BudgetExhausted` arrives on the
/// PerformanceBudget stream.
class ViewportPerformanceBudgetExhausted extends ViewportRenderBudgetEvent {
  const ViewportPerformanceBudgetExhausted();
}

/// Internal event injected when a `BudgetWarning` arrives on the
/// DataBudget stream.
class ViewportDataBudgetWarning extends ViewportRenderBudgetEvent {
  const ViewportDataBudgetWarning();
}

/// Internal event injected when a `BudgetExhausted` arrives on the
/// DataBudget stream.
class ViewportDataBudgetExhausted extends ViewportRenderBudgetEvent {
  const ViewportDataBudgetExhausted();
}

/// Reset event: integrator-driven. Returns fidelity to HIGH.
class ViewportBudgetReset extends ViewportRenderBudgetEvent {
  const ViewportBudgetReset();
}

/// State emitted by [ViewportRenderBudgetBloc].
class ViewportRenderState extends Equatable {
  /// Current recommended fidelity for the integrator HMI.
  final RenderFidelity fidelity;

  /// `true` when PerformanceBudget has fired Warning at least once
  /// since last reset.
  final bool performanceWarningSeen;

  /// `true` when PerformanceBudget has fired Exhausted at least once
  /// since last reset.
  final bool performanceExhaustedSeen;

  /// `true` when DataBudget has fired Warning at least once since
  /// last reset.
  final bool dataWarningSeen;

  /// `true` when DataBudget has fired Exhausted at least once since
  /// last reset.
  final bool dataExhaustedSeen;

  const ViewportRenderState({
    required this.fidelity,
    this.performanceWarningSeen = false,
    this.performanceExhaustedSeen = false,
    this.dataWarningSeen = false,
    this.dataExhaustedSeen = false,
  });

  /// Initial state: high fidelity, no warnings observed.
  const ViewportRenderState.initial()
      : fidelity = RenderFidelity.high,
        performanceWarningSeen = false,
        performanceExhaustedSeen = false,
        dataWarningSeen = false,
        dataExhaustedSeen = false;

  ViewportRenderState copyWith({
    RenderFidelity? fidelity,
    bool? performanceWarningSeen,
    bool? performanceExhaustedSeen,
    bool? dataWarningSeen,
    bool? dataExhaustedSeen,
  }) {
    return ViewportRenderState(
      fidelity: fidelity ?? this.fidelity,
      performanceWarningSeen:
          performanceWarningSeen ?? this.performanceWarningSeen,
      performanceExhaustedSeen:
          performanceExhaustedSeen ?? this.performanceExhaustedSeen,
      dataWarningSeen: dataWarningSeen ?? this.dataWarningSeen,
      dataExhaustedSeen: dataExhaustedSeen ?? this.dataExhaustedSeen,
    );
  }

  @override
  List<Object?> get props => [
        fidelity,
        performanceWarningSeen,
        performanceExhaustedSeen,
        dataWarningSeen,
        dataExhaustedSeen,
      ];
}

/// Bloc composing PerformanceBudget + DataBudget streams into a
/// single `ViewportRenderState` with a `RenderFidelity` recommendation.
///
/// See library-level documentation for the caution-add-direction-wins
/// composition rule + per-cohort floor invariants.
class ViewportRenderBudgetBloc
    extends Bloc<ViewportRenderBudgetEvent, ViewportRenderState> {
  ViewportRenderBudgetBloc({
    ViewportRenderConfig config = const ViewportRenderConfig(),
  })  : _config = config,
        super(const ViewportRenderState.initial()) {
    on<ViewportPerformanceBudgetWarning>(_onPerfWarning);
    on<ViewportPerformanceBudgetExhausted>(_onPerfExhausted);
    on<ViewportDataBudgetWarning>(_onDataWarning);
    on<ViewportDataBudgetExhausted>(_onDataExhausted);
    on<ViewportBudgetReset>(_onReset);
  }

  final ViewportRenderConfig _config;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Active configuration.
  ViewportRenderConfig get config => _config;

  /// Subscribe to a `PerformanceBudget.budgetEvents` stream. The bloc
  /// dispatches the appropriate `Viewport*` event for each emitted
  /// `BudgetWarning` / `BudgetExhausted`.
  ///
  /// `T` is the event-class type from the source stream. The function
  /// inspects runtime type via `event.runtimeType.toString()` to
  /// avoid a hard dependency on the source package's sealed class
  /// (offline_tiles + snow_rendering each export their own
  /// `BudgetWarning` / `BudgetExhausted`; using `Object` here keeps
  /// this bloc compatible with both without re-importing).
  void attachPerformanceBudgetStream(Stream<Object> stream) {
    _subscriptions.add(stream.listen((event) {
      final name = event.runtimeType.toString();
      if (name == 'BudgetWarning') {
        add(const ViewportPerformanceBudgetWarning());
      } else if (name == 'BudgetExhausted') {
        add(const ViewportPerformanceBudgetExhausted());
      }
    }));
  }

  /// Subscribe to a `DataBudget.budgetEvents` stream. See
  /// [attachPerformanceBudgetStream] for the runtime-type inspection
  /// rationale.
  void attachDataBudgetStream(Stream<Object> stream) {
    _subscriptions.add(stream.listen((event) {
      final name = event.runtimeType.toString();
      if (name == 'BudgetWarning') {
        add(const ViewportDataBudgetWarning());
      } else if (name == 'BudgetExhausted') {
        add(const ViewportDataBudgetExhausted());
      }
      // RenderFidelityDrop is a snow_rendering-specific event and is
      // already covered by the BudgetExhausted lock-step emit; no
      // additional handling needed here.
    }));
  }

  /// Compute the recommended fidelity from the new state, applying the
  /// per-cohort floor. The floor never RAISES fidelity; it only
  /// prevents the bloc from going BELOW the floor.
  RenderFidelity _resolveFidelityWithFloor(RenderFidelity proposed) {
    if (_config.floor == RenderFidelityFloor.medium &&
        proposed == RenderFidelity.low) {
      return RenderFidelity.medium;
    }
    return proposed;
  }

  /// Decide the proposed fidelity from the new flag state.
  ///
  /// **Caution-add-direction-wins**: any Exhausted → LOW; otherwise
  /// any Warning → MEDIUM; else HIGH.
  RenderFidelity _proposedFromFlags({
    required bool perfExhausted,
    required bool dataExhausted,
    required bool perfWarning,
    required bool dataWarning,
  }) {
    if (perfExhausted || dataExhausted) {
      return RenderFidelity.low;
    }
    if (perfWarning || dataWarning) {
      return RenderFidelity.medium;
    }
    return RenderFidelity.high;
  }

  void _onPerfWarning(
    ViewportPerformanceBudgetWarning event,
    Emitter<ViewportRenderState> emit,
  ) {
    final next = state.copyWith(performanceWarningSeen: true);
    final proposed = _proposedFromFlags(
      perfExhausted: next.performanceExhaustedSeen,
      dataExhausted: next.dataExhaustedSeen,
      perfWarning: next.performanceWarningSeen,
      dataWarning: next.dataWarningSeen,
    );
    emit(next.copyWith(fidelity: _resolveFidelityWithFloor(proposed)));
  }

  void _onPerfExhausted(
    ViewportPerformanceBudgetExhausted event,
    Emitter<ViewportRenderState> emit,
  ) {
    final next = state.copyWith(performanceExhaustedSeen: true);
    final proposed = _proposedFromFlags(
      perfExhausted: next.performanceExhaustedSeen,
      dataExhausted: next.dataExhaustedSeen,
      perfWarning: next.performanceWarningSeen,
      dataWarning: next.dataWarningSeen,
    );
    emit(next.copyWith(fidelity: _resolveFidelityWithFloor(proposed)));
  }

  void _onDataWarning(
    ViewportDataBudgetWarning event,
    Emitter<ViewportRenderState> emit,
  ) {
    final next = state.copyWith(dataWarningSeen: true);
    final proposed = _proposedFromFlags(
      perfExhausted: next.performanceExhaustedSeen,
      dataExhausted: next.dataExhaustedSeen,
      perfWarning: next.performanceWarningSeen,
      dataWarning: next.dataWarningSeen,
    );
    emit(next.copyWith(fidelity: _resolveFidelityWithFloor(proposed)));
  }

  void _onDataExhausted(
    ViewportDataBudgetExhausted event,
    Emitter<ViewportRenderState> emit,
  ) {
    final next = state.copyWith(dataExhaustedSeen: true);
    final proposed = _proposedFromFlags(
      perfExhausted: next.performanceExhaustedSeen,
      dataExhausted: next.dataExhaustedSeen,
      perfWarning: next.performanceWarningSeen,
      dataWarning: next.dataWarningSeen,
    );
    emit(next.copyWith(fidelity: _resolveFidelityWithFloor(proposed)));
  }

  void _onReset(
    ViewportBudgetReset event,
    Emitter<ViewportRenderState> emit,
  ) {
    emit(const ViewportRenderState.initial());
  }

  @override
  Future<void> close() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
