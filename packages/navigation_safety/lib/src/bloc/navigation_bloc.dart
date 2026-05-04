/// Navigation session BLoC with advisory safety alerts.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'navigation_event.dart';
import 'navigation_state.dart';

/// Returns true if [incoming] severity should replace [current].
/// Prevents alert downgrade: lower severity never replaces higher.
///
/// Uses `.index` for ordering. The semantics rely on enum declaration
/// order in `AlertSeverity` (info < warning < critical) and are locked
/// by `severity_ordering_lock_test.dart`. Adding or reordering enum
/// values requires updating that test deliberately.
bool _canUpdateSeverity(AlertSeverity incoming, AlertSeverity? current) {
  if (current == null) return true;
  return incoming.index >= current.index;
}

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  NavigationBloc({
    DriverProfile? profile,
    AlertDensityThrottle? throttle,
    LoomFitTelemetry? telemetry,
  })  : _profile = profile,
        _throttle = throttle,
        _telemetry = telemetry,
        super(const NavigationState.idle()) {
    on<NavigationStarted>(_onStarted);
    on<NavigationStopped>(_onStopped);
    on<ManeuverAdvanced>(_onManeuverAdvanced);
    on<RouteDeviationDetected>(_onDeviation);
    on<RerouteCompleted>(_onRerouteCompleted);
    on<SafetyAlertReceived>(_onSafetyAlert);
    on<SafetyAlertDismissed>(_onAlertDismissed);
  }

  /// Active driver profile, when supplied. Null preserves pre-0.8.0
  /// back-compat (no per-profile throttling, no explainer rendering).
  final DriverProfile? _profile;

  /// Per-profile alert-density throttle. Lazily constructed on first
  /// `_onSafetyAlert` if [_profile] is non-null and no throttle was
  /// supplied to the constructor.
  AlertDensityThrottle? _throttle;

  /// Optional emit-only telemetry stream for fired / dropped /
  /// criticalBypass / coldStart outcomes. Null preserves back-compat
  /// (no records emitted).
  final LoomFitTelemetry? _telemetry;

  void _onStarted(
    NavigationStarted event,
    Emitter<NavigationState> emit,
  ) {
    // Only allow starting from idle or arrived.
    // Deviated routes must complete via RerouteCompleted, not NavigationStarted.
    if (state.status != NavigationStatus.idle &&
        state.status != NavigationStatus.arrived) {
      assert(
        false,
        'NavigationStarted fired in unexpected state: ${state.status}',
      );
      return;
    }
    emit(NavigationState(
      status: NavigationStatus.navigating,
      route: event.route,
      currentManeuverIndex: 0,
      destinationLabel: event.destinationLabel,
      alertMessage: state.alertMessage,
      alertSeverity: state.alertSeverity,
      alertDismissible: state.alertDismissible,
      alertScenario: state.alertScenario,
    ));
  }

  void _onStopped(
    NavigationStopped event,
    Emitter<NavigationState> emit,
  ) {
    emit(NavigationState(
      status: NavigationStatus.idle,
      alertMessage: state.alertMessage,
      alertSeverity: state.alertSeverity,
      alertDismissible: state.alertDismissible,
      alertScenario: state.alertScenario,
    ));
  }

  void _onManeuverAdvanced(
    ManeuverAdvanced event,
    Emitter<NavigationState> emit,
  ) {
    if (state.status != NavigationStatus.navigating) return;
    if (state.route == null) return;

    final nextIndex = state.currentManeuverIndex + 1;
    final totalManeuvers = state.route!.maneuvers.length;

    if (totalManeuvers == 0 || nextIndex >= totalManeuvers) {
      emit(state.copyWith(
        status: NavigationStatus.arrived,
        currentManeuverIndex: totalManeuvers > 0 ? totalManeuvers - 1 : 0,
      ));
    } else {
      emit(state.copyWith(currentManeuverIndex: nextIndex));
    }
  }

  void _onDeviation(
    RouteDeviationDetected event,
    Emitter<NavigationState> emit,
  ) {
    if (state.status != NavigationStatus.navigating) return;

    emit(state.copyWith(status: NavigationStatus.deviated));
  }

  void _onRerouteCompleted(
    RerouteCompleted event,
    Emitter<NavigationState> emit,
  ) {
    if (state.status != NavigationStatus.deviated) return;

    emit(state.copyWith(
      status: NavigationStatus.navigating,
      route: event.newRoute,
      currentManeuverIndex: 0,
      // Only clear dismissible alerts — non-dismissible safety alerts persist
      // through reroutes (e.g. "ice road ahead" must not be silenced by reroute).
      clearAlert: state.alertDismissible,
    ));
  }

  void _onSafetyAlert(
    SafetyAlertReceived event,
    Emitter<NavigationState> emit,
  ) {
    if (!_canUpdateSeverity(event.severity, state.alertSeverity)) return;

    final Stopwatch? sw = kDebugMode ? (Stopwatch()..start()) : null;

    // Per-profile alert-density throttle (0.8.0). Active only when a
    // driver profile was supplied to the bloc; lazy-constructs on
    // first call so apps that never supply a profile pay no
    // construction cost. Critical alerts always fire by documented
    // invariant; the throttle protects info / warning tiers from
    // desensitization.
    LoomFitOutcome? outcome;
    if (_profile != null) {
      _throttle ??= AlertDensityThrottle.forProfile(_profile);
      final now = DateTime.now();
      // Cold-start = first call against a fresh throttle.
      final coldStart = _throttle!.currentWindowCount(now) == 0;
      final permitted = _throttle!.shouldFire(now, event.severity);

      if (!permitted) {
        // Dropped by throttle. Emit telemetry (if subscribed) and
        // return without state change — the alert does not surface
        // to the driver.
        outcome = LoomFitOutcome.droppedByThrottle;
        _emitTelemetry(event, now, outcome);
        return;
      }

      // Permitted — classify cold-start / critical-bypass / fired.
      if (coldStart) {
        outcome = LoomFitOutcome.coldStart;
      } else if (event.severity == AlertSeverity.critical) {
        outcome = LoomFitOutcome.criticalBypass;
      } else {
        outcome = LoomFitOutcome.fired;
      }
      _emitTelemetry(event, now, outcome);
    }

    // Action-coupled message resolution (0.8.0). When the event carries
    // a road-surface condition AND the bloc has a driver profile, the
    // explainer's per-(condition, profile) action string replaces the
    // free-form message. Otherwise the free-form message is used
    // verbatim (back-compat).
    final message = (event.condition != null && _profile != null)
        ? AlertExplainer.forConditionAndProfile(event.condition!, _profile)
            .action
        : event.message;

    emit(state.copyWith(
      alertMessage: message,
      alertSeverity: event.severity,
      alertDismissible: event.dismissible,
      alertScenario: event.scenario,
      alertCondition: event.condition,
    ));

    assert(() {
      sw?.stop();
      final elapsed = sw?.elapsedMilliseconds ?? 0;
      if (elapsed > 500) {
        // ignore: avoid_print
        print(
          '[navigation_safety] LATENCY WARNING: SafetyAlertReceived '
          'processing took ${elapsed}ms (OODA orient budget: 500ms)',
        );
      }
      return true;
    }());
  }

  /// Emit a telemetry record onto the configured `LoomFitTelemetry`
  /// stream when one was supplied to the bloc. No-op when the bloc
  /// has no telemetry instance.
  void _emitTelemetry(
    SafetyAlertReceived event,
    DateTime now,
    LoomFitOutcome outcome,
  ) {
    final telemetry = _telemetry;
    if (telemetry == null) return;
    if (_profile == null) return;
    telemetry.record(LoomFitTelemetryRecord(
      profileClass: _profile,
      ambientThreshold: event.ambientThreshold,
      alertSequence: <DateTime>[now],
      responseLatency: null,
      outcome: outcome,
    ));
  }

  void _onAlertDismissed(
    SafetyAlertDismissed event,
    Emitter<NavigationState> emit,
  ) {
    if (!state.alertDismissible) return;

    emit(state.copyWith(clearAlert: true));
  }
}
