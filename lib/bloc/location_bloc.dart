/// LocationBloc — 6-state quality machine for GPS signal.
///
/// Consumes a [LocationProvider] and emits [LocationState] transitions
/// based on signal quality, staleness, and errors.
///
/// The BLoC is pure logic — no D-Bus, no Flutter widgets. Fully testable
/// with a mock provider.
///
/// Location pipeline BLoC: provider-agnostic, fully testable with mocks.
library;

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:kalman_dr/kalman_dr.dart';
import 'location_event.dart';
import 'location_state.dart';

class LocationBloc extends Bloc<LocationEvent, LocationState> {
  final LocationProvider _provider;
  final Duration staleThreshold;

  StreamSubscription<GeoPosition>? _positionSub;
  Timer? _staleTimer;

  LocationBloc({
    required LocationProvider provider,
    this.staleThreshold = const Duration(seconds: 10),
  })  : _provider = provider,
        super(const LocationState.uninitialized()) {
    on<LocationStartRequested>(_onStart);
    on<LocationStopRequested>(_onStop);
    on<LocationPositionReceived>(_onPositionReceived);
    on<LocationStaleTimeout>(_onStaleTimeout);
    on<LocationErrorOccurred>(_onError);
  }

  Future<void> _onStart(
    LocationStartRequested event,
    Emitter<LocationState> emit,
  ) async {
    if (state.isTracking) return;

    emit(const LocationState.acquiring());

    try {
      await _provider.start();
      _positionSub = _provider.positions.listen(
        (pos) => add(LocationPositionReceived(pos)),
        onError: (Object e) => add(LocationErrorOccurred(e.toString())),
      );
    } catch (e) {
      emit(LocationState(
        quality: LocationQuality.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onStop(
    LocationStopRequested event,
    Emitter<LocationState> emit,
  ) async {
    _cancelStaleTimer();
    await _positionSub?.cancel();
    _positionSub = null;

    try {
      await _provider.stop();
    } catch (_) {}

    emit(const LocationState.uninitialized());
  }

  void _onPositionReceived(
    LocationPositionReceived event,
    Emitter<LocationState> emit,
  ) {
    final pos = event.position;

    // Reset stale timer on every position update.
    _resetStaleTimer();

    // Detect dead reckoning status from the provider.
    final provider = _provider;
    final isDr = provider is DeadReckoningProvider && provider.isDrActive;

    if (pos.isNavigationGrade) {
      emit(LocationState(
        quality: LocationQuality.fix,
        position: pos,
        isDeadReckoning: isDr,
      ));
    } else {
      emit(LocationState(
        quality: LocationQuality.degraded,
        position: pos,
        isDeadReckoning: isDr,
      ));
    }
  }

  void _onStaleTimeout(
    LocationStaleTimeout event,
    Emitter<LocationState> emit,
  ) {
    // Only transition to stale if we had a fix or degraded state.
    if (state.quality == LocationQuality.fix ||
        state.quality == LocationQuality.degraded) {
      emit(state.copyWith(quality: LocationQuality.stale));
    }
  }

  void _onError(
    LocationErrorOccurred event,
    Emitter<LocationState> emit,
  ) {
    _cancelStaleTimer();
    emit(LocationState(
      quality: LocationQuality.error,
      errorMessage: event.message,
    ));
  }

  void _resetStaleTimer() {
    _cancelStaleTimer();
    _staleTimer = Timer(staleThreshold, () {
      add(const LocationStaleTimeout());
    });
  }

  void _cancelStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  @override
  Future<void> close() async {
    _cancelStaleTimer();
    await _positionSub?.cancel();
    await _provider.dispose();
    return super.close();
  }
}
