/// MapBloc — declarative map viewport state machine.
///
/// Manages viewport center, zoom, camera mode, layer visibility,
/// and fit-to-bounds requests. Purely declarative — the widget reads
/// [MapState] and reconciles with [MapController].
///
/// MapBloc has no external dependencies. It is a pure state machine.
///
/// BLoCs target ~80 lines for single-responsibility.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import 'map_event.dart';
import 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc() : super(const MapState.loading()) {
    on<MapInitialized>(_onInitialized);
    on<CameraModeChanged>(_onCameraModeChanged);
    on<CenterChanged>(_onCenterChanged);
    on<ZoomChanged>(_onZoomChanged);
    on<FitToBounds>(_onFitToBounds);
    on<LayerToggled>(_onLayerToggled);
    on<UserPanDetected>(_onUserPan);
  }

  void _onInitialized(
    MapInitialized event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(
      status: MapStatus.ready,
      center: event.center,
      zoom: event.zoom,
    ));
  }

  void _onCameraModeChanged(
    CameraModeChanged event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(
      cameraMode: event.mode,
      clearFitBounds: event.mode != CameraMode.overview,
    ));
  }

  void _onCenterChanged(
    CenterChanged event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(center: event.center));
  }

  void _onZoomChanged(
    ZoomChanged event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(zoom: event.zoom));
  }

  void _onFitToBounds(
    FitToBounds event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(
      cameraMode: CameraMode.overview,
      fitBoundsSw: event.southWest,
      fitBoundsNe: event.northEast,
    ));
  }

  void _onLayerToggled(
    LayerToggled event,
    Emitter<MapState> emit,
  ) {
    final layers = Set<MapLayerType>.from(state.visibleLayers);
    if (event.visible) {
      layers.add(event.layer);
    } else {
      layers.remove(event.layer);
    }
    emit(state.copyWith(visibleLayers: layers));
  }

  void _onUserPan(
    UserPanDetected event,
    Emitter<MapState> emit,
  ) {
    // User gesture → exit follow/overview, enter freeLook.
    if (state.cameraMode == CameraMode.freeLook) return;

    emit(state.copyWith(
      cameraMode: CameraMode.freeLook,
      clearFitBounds: true,
    ));
  }
}
