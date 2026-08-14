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
    // Prevent double-start while already acquiring or tracking,
    // but allow restart from error state (state machine: error → acquiring).
    if (state.quality == LocationQuality.acquiring ||
        state.quality == LocationQuality.fix ||
        state.quality == LocationQuality.degraded ||
        state.quality == LocationQuality.stale) {
      return;
    }

    // Cancel any stale subscription before creating a new one.
    await _positionSub?.cancel();
    _positionSub = null;

    emit(const LocationState.acquiring());

    try {
      _positionSub = _provider.positions.listen(
        (pos) => add(LocationPositionReceived(pos)),
        onError: (Object e) => add(LocationErrorOccurred(e.toString())),
      );
      await _provider.start();
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

    // L1 finiteness guard — the PRIMARY guard for HER in the compound-failure
    // GPS scenario (Maps fail + GPS degraded). On the live GeoClue / Kalman-DR
    // path a non-finite latitude or longitude can reach the map boundary:
    // flutter_map 8.2.2 SILENTLY projects a non-finite coordinate to garbage
    // (teleporting her dot, wrecking the follow camera, with NO throw), while
    // 8.3.0 throws outright. We mirror flutter_map's own `isFinite` condition
    // and DROP a poisoned fix at this chokepoint — every map boundary (the
    // follow camera in snow_scene_scaffold, the position marker in map_layer,
    // route_follower) reads LocationState.position, so guarding here covers
    // them all, version-independently. The last good LocationState is retained
    // (we do NOT emit) and the stale watchdog is NOT reset, so a stream of
    // garbage correctly ages to `stale` rather than masquerading as a live fix.
    //
    // A non-finite *accuracy* alone is NOT a poison and does NOT drop the fix:
    // accuracy never reaches the map boundary (only lat/lon do), and
    // GeoPosition already uses a non-finite value to mean "unknown". An unknown
    // accuracy correctly fails `isNavigationGrade` (accuracy <= 50.0 is false
    // for NaN) and flows to the `degraded` branch below — exactly the right
    // signal, with no valid coordinate dropped.
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) {
      return;
    }

    // Reset stale timer on every (valid) position update.
    _resetStaleTimer();

    // Dead-reckoning status comes from the POSITION, not from the provider.
    //
    // `provider.isDrActive` is read here, in the event handler — but the
    // position was emitted earlier and reached us through the BLoC event queue.
    // In that gap the provider can flip: a returning GPS fix calls _stopDr()
    // synchronously inside the provider's own listener, so a genuinely
    // dead-reckoned position that is still queued gets labelled as a live fix,
    // and her dot is shown as measured when it was invented. The object's own
    // testimony is emitted-time truth and cannot drift.
    //
    // The provider read survives only as the fallback for a provider that has
    // not adopted `PositionSource` — never as an override of what the position
    // itself declares.
    final provider = _provider;
    final isDr = switch (pos.source) {
      PositionSource.deadReckoned => true,
      PositionSource.measured || PositionSource.fused => false,
      PositionSource.unknown =>
        provider is DeadReckoningProvider && provider.isDrActive,
    };

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
    // Dead reckoning is actively estimating position — not stale.
    // Rearm the watchdog so it keeps firing during DR.
    if (state.isDeadReckoning) {
      _resetStaleTimer();
      return;
    }
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
