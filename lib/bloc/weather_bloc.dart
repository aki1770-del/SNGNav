/// WeatherBloc — weather condition monitoring state machine.
///
/// Consumes a [WeatherProvider] and emits [WeatherState] transitions
/// based on condition updates from the provider stream.
///
/// The BLoC is pure logic — no HTTP, no simulated data. Fully testable
/// with a mock provider.
///
/// Widget integration:
///   - Weather overlay reads [WeatherState.condition] for map layer tinting
///   - If [WeatherState.isHazardous], widget dispatches [SafetyAlertReceived]
///     to [NavigationBloc] — widget-mediated, no direct BLoC coupling
///
/// Core snow-scenario BLoC for weather condition monitoring.
library;

import 'dart:async';

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'weather_event.dart';
import 'weather_state.dart';

class WeatherBloc extends Bloc<WeatherEvent, WeatherState> {
  final WeatherProvider _provider;

  StreamSubscription<dynamic>? _conditionSub;
  // Guards the async gap between the isMonitoring check and the state emit.
  // Without this, two concurrent WeatherMonitorStarted events can both pass
  // the isMonitoring guard before either emits.
  bool _startingUp = false;

  WeatherBloc({
    required WeatherProvider provider,
  })  : _provider = provider,
        super(const WeatherState.unavailable()) {
    on<WeatherMonitorStarted>(_onStart);
    on<WeatherMonitorStopped>(_onStop);
    on<WeatherConditionReceived>(_onConditionReceived);
    on<WeatherStaleConditionReceived>(_onStaleConditionReceived);
    on<WeatherConditionUnavailable>(_onConditionUnavailable);
    on<WeatherErrorOccurred>(_onError);
  }

  Future<void> _onStart(
    WeatherMonitorStarted event,
    Emitter<WeatherState> emit,
  ) async {
    if (state.isMonitoring || _startingUp) return;
    _startingUp = true;

    // Cancel any previous subscription before starting a new one
    // (guards against retry after error state without an intervening stop).
    await _conditionSub?.cancel();
    _conditionSub = null;

    emit(state.copyWith(status: WeatherStatus.monitoring));

    try {
      // driving_weather 0.5.0: the provider stream is a SEALED WeatherReading —
      // observed / stale / unavailable — not a bare WeatherCondition. The three
      // cases are genuinely different facts and the app must not flatten them:
      // a stale reading is not a fresh one, and "no data" is not "no hazard".
      _conditionSub = _provider.conditions.listen(
        (reading) {
          switch (reading) {
            case WeatherObserved(:final condition):
              add(WeatherConditionReceived(condition));
            case WeatherStale(:final lastKnown, :final age):
              add(WeatherStaleConditionReceived(lastKnown, age));
            case WeatherUnavailable():
              add(const WeatherConditionUnavailable());
          }
        },
        onError: (Object e) => add(WeatherErrorOccurred(e.toString())),
      );
      await _provider.startMonitoring();
    } catch (e) {
      emit(WeatherState(
        status: WeatherStatus.error,
        errorMessage: e.toString(),
      ));
    } finally {
      _startingUp = false;
    }
  }

  Future<void> _onStop(
    WeatherMonitorStopped event,
    Emitter<WeatherState> emit,
  ) async {
    await _conditionSub?.cancel();
    _conditionSub = null;

    try {
      await _provider.stopMonitoring();
    } catch (_) {}

    emit(const WeatherState.unavailable());
  }

  void _onConditionReceived(
    WeatherConditionReceived event,
    Emitter<WeatherState> emit,
  ) {
    emit(state.copyWith(
      status: WeatherStatus.monitoring,
      condition: event.condition,
      conditionAge: Duration.zero,
    ));
  }

  void _onStaleConditionReceived(
    WeatherStaleConditionReceived event,
    Emitter<WeatherState> emit,
  ) {
    // The last known condition, carried with its REAL age. It is not presented
    // as fresh, and it is not thrown away — an hour-old reading is still
    // information, as long as she is told it is an hour old.
    emit(state.copyWith(
      status: WeatherStatus.monitoring,
      condition: event.lastKnown,
      conditionAge: event.age,
    ));
  }

  void _onConditionUnavailable(
    WeatherConditionUnavailable event,
    Emitter<WeatherState> emit,
  ) {
    // No condition at all. NOT "no hazard" — the state carries null, and every
    // verdict on it resolves to SafetyVerdict.unknown.
    emit(state.copyWith(
      status: WeatherStatus.monitoring,
      clearCondition: true,
    ));
  }

  void _onError(
    WeatherErrorOccurred event,
    Emitter<WeatherState> emit,
  ) {
    // Preserve the last known condition so a positive hazard verdict survives
    // an error. It keeps whatever age it already carried — an error does not
    // make an old reading fresh.
    emit(state.copyWith(
      status: WeatherStatus.error,
      errorMessage: event.message,
    ));
  }

  @override
  Future<void> close() async {
    await _conditionSub?.cancel();
    _provider.dispose();
    return super.close();
  }
}
