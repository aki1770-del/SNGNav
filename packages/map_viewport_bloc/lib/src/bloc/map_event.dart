/// Inputs for the map viewport state machine.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import '../models/map_viewport_models.dart';

sealed class MapEvent extends Equatable {
  const MapEvent();

  @override
  List<Object?> get props => [];
}

class MapInitialized extends MapEvent {
  const MapInitialized({
    required this.center,
    required this.zoom,
  });

  final LatLng center;
  final double zoom;

  @override
  List<Object?> get props => [center, zoom];
}

class CameraModeChanged extends MapEvent {
  const CameraModeChanged(this.mode);

  final CameraMode mode;

  @override
  List<Object?> get props => [mode];
}

class CenterChanged extends MapEvent {
  const CenterChanged(this.center);

  final LatLng center;

  @override
  List<Object?> get props => [center];
}

class ZoomChanged extends MapEvent {
  const ZoomChanged(this.zoom);

  final double zoom;

  @override
  List<Object?> get props => [zoom];
}

class FitToBounds extends MapEvent {
  const FitToBounds({
    required this.southWest,
    required this.northEast,
  });

  final LatLng southWest;
  final LatLng northEast;

  @override
  List<Object?> get props => [southWest, northEast];
}

class LayerToggled extends MapEvent {
  const LayerToggled({
    required this.layer,
    required this.visible,
  });

  final MapLayerType layer;
  final bool visible;

  @override
  List<Object?> get props => [layer, visible];
}

class UserPanDetected extends MapEvent {
  const UserPanDetected();
}

class FreeLookTimeoutElapsed extends MapEvent {
  const FreeLookTimeoutElapsed();
}