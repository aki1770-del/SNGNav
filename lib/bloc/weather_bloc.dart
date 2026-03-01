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

import 'package:flutter_bloc/flutter_bloc.dart';

import '../providers/weather_provider.dart';
import 'weather_event.dart';
import 'weather_state.dart';

class WeatherBloc extends Bloc<WeatherEvent, WeatherState> {
  final WeatherProvider _provider;

  StreamSubscription<dynamic>? _conditionSub;

  WeatherBloc({
    required WeatherProvider provider,
  })  : _provider = provider,
        super(const WeatherState.unavailable()) {
    on<WeatherMonitorStarted>(_onStart);
    on<WeatherMonitorStopped>(_onStop);
    on<WeatherConditionReceived>(_onConditionReceived);
    on<WeatherErrorOccurred>(_onError);
  }

  Future<void> _onStart(
    WeatherMonitorStarted event,
    Emitter<WeatherState> emit,
  ) async {
    if (state.isMonitoring) return;

    emit(state.copyWith(status: WeatherStatus.monitoring));

    try {
      await _provider.startMonitoring();
      _conditionSub = _provider.conditions.listen(
        (condition) => add(WeatherConditionReceived(condition)),
        onError: (Object e) => add(WeatherErrorOccurred(e.toString())),
      );
    } catch (e) {
      emit(WeatherState(
        status: WeatherStatus.error,
        errorMessage: e.toString(),
      ));
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
    ));
  }

  void _onError(
    WeatherErrorOccurred event,
    Emitter<WeatherState> emit,
  ) {
    emit(WeatherState(
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
