/// Declarative map viewport state machine.
library;

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../models/map_viewport_models.dart';
import 'map_event.dart';
import 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc({
    this.freeLookTimeout = const Duration(seconds: 10),
    this.initialCenter = kDefaultMapCenter,
    this.initialZoom = kDefaultFollowZoom,
    Set<MapLayerType> initialVisibleLayers = kDefaultVisibleLayers,
  })  : initialVisibleLayers = Set<MapLayerType>.unmodifiable(initialVisibleLayers),
        super(
          MapState.loading(
            center: initialCenter,
            zoom: initialZoom,
            visibleLayers: initialVisibleLayers,
          ),
        ) {
    on<MapInitialized>(_onInitialized);
    on<CameraModeChanged>(_onCameraModeChanged);
    on<CenterChanged>(_onCenterChanged);
    on<ZoomChanged>(_onZoomChanged);
    on<FitToBounds>(_onFitToBounds);
    on<LayerToggled>(_onLayerToggled);
    on<UserPanDetected>(_onUserPanDetected);
    on<FreeLookTimeoutElapsed>(_onFreeLookTimeoutElapsed);
  }

  final Duration freeLookTimeout;
  final LatLng initialCenter;
  final double initialZoom;
  final Set<MapLayerType> initialVisibleLayers;

  Timer? _freeLookTimer;

  void _onInitialized(MapInitialized event, Emitter<MapState> emit) {
    emit(
      state.copyWith(
        status: MapStatus.ready,
        center: event.center,
        zoom: event.zoom,
      ),
    );
  }

  void _onCameraModeChanged(
    CameraModeChanged event,
    Emitter<MapState> emit,
  ) {
    if (event.mode == CameraMode.freeLook) {
      _scheduleFreeLookTimeout();
    } else {
      _cancelFreeLookTimeout();
    }

    final nextState = state.copyWith(
      cameraMode: event.mode,
      clearFitBounds: event.mode != CameraMode.overview,
    );
    if (nextState != state) {
      emit(nextState);
    }
  }

  void _onCenterChanged(CenterChanged event, Emitter<MapState> emit) {
    emit(state.copyWith(center: event.center));
  }

  void _onZoomChanged(ZoomChanged event, Emitter<MapState> emit) {
    // Clamp to valid tile server range. Values outside [1, 22] produce blank
    // tiles or divide-by-zero in mercator math.
    emit(state.copyWith(zoom: event.zoom.clamp(1.0, 22.0)));
  }

  void _onFitToBounds(FitToBounds event, Emitter<MapState> emit) {
    _cancelFreeLookTimeout();
    emit(
      state.copyWith(
        cameraMode: CameraMode.overview,
        fitBoundsSw: event.southWest,
        fitBoundsNe: event.northEast,
      ),
    );
  }

  void _onLayerToggled(LayerToggled event, Emitter<MapState> emit) {
    if (!event.layer.isUserToggleable) {
      return;
    }

    final visibleLayers = Set<MapLayerType>.from(state.visibleLayers);
    if (event.visible) {
      visibleLayers.add(event.layer);
    } else {
      visibleLayers.remove(event.layer);
    }

    if (visibleLayers.length == state.visibleLayers.length &&
        visibleLayers.containsAll(state.visibleLayers)) {
      return;
    }

    emit(state.copyWith(visibleLayers: visibleLayers));
  }

  void _onUserPanDetected(UserPanDetected event, Emitter<MapState> emit) {
    _scheduleFreeLookTimeout();
    if (state.cameraMode == CameraMode.freeLook) {
      return;
    }

    emit(
      state.copyWith(
        cameraMode: CameraMode.freeLook,
        clearFitBounds: true,
      ),
    );
  }

  void _onFreeLookTimeoutElapsed(
    FreeLookTimeoutElapsed event,
    Emitter<MapState> emit,
  ) {
    if (state.cameraMode != CameraMode.freeLook) {
      return;
    }

    _cancelFreeLookTimeout();
    emit(
      state.copyWith(
        cameraMode: CameraMode.follow,
        clearFitBounds: true,
      ),
    );
  }

  void _scheduleFreeLookTimeout() {
    _cancelFreeLookTimeout();
    _freeLookTimer = Timer(freeLookTimeout, () {
      if (!isClosed) {
        add(const FreeLookTimeoutElapsed());
      }
    });
  }

  void _cancelFreeLookTimeout() {
    _freeLookTimer?.cancel();
    _freeLookTimer = null;
  }

  @override
  Future<void> close() {
    _cancelFreeLookTimeout();
    return super.close();
  }
}