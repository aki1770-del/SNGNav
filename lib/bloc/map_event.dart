/// Map events — inputs to the MapBloc state machine.
///
/// MapBloc manages *declarative* map state: viewport center, zoom,
/// camera mode, and layer visibility. The widget reads MapState and
/// reconciles with MapController — MapBloc never holds a controller.
///
/// Events cover viewport changes, camera mode switches, and layer toggling.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'map_state.dart';

sealed class MapEvent extends Equatable {
  const MapEvent();

  @override
  List<Object?> get props => [];
}

/// Map has loaded and is ready for interaction.
class MapInitialized extends MapEvent {
  final LatLng center;
  final double zoom;

  const MapInitialized({
    required this.center,
    required this.zoom,
  });

  @override
  List<Object?> get props => [center, zoom];
}

/// Camera mode changed (follow, freeLook, overview).
///
/// Dispatched by the widget in response to:
///   - User taps follow toggle → follow
///   - User pans map → freeLook (via UserPanDetected)
///   - Route received → overview (via FitToBounds)
class CameraModeChanged extends MapEvent {
  final CameraMode mode;

  const CameraModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

/// Viewport center changed (follow mode position update or manual).
class CenterChanged extends MapEvent {
  final LatLng center;

  const CenterChanged(this.center);

  @override
  List<Object?> get props => [center];
}

/// Zoom level changed.
class ZoomChanged extends MapEvent {
  final double zoom;

  const ZoomChanged(this.zoom);

  @override
  List<Object?> get props => [zoom];
}

/// Fit the viewport to a bounding box (route bounds, etc.).
///
/// Sets camera mode to overview and stores bounds for the widget
/// to apply via MapController.fitCamera().
class FitToBounds extends MapEvent {
  final LatLng southWest;
  final LatLng northEast;

  const FitToBounds({
    required this.southWest,
    required this.northEast,
  });

  @override
  List<Object?> get props => [southWest, northEast];
}

/// Toggle a map layer's visibility.
///
/// Layers: route, weather, safety, fleet.
/// Default visible: {route}. Others toggle on as features are built.
class LayerToggled extends MapEvent {
  final MapLayerType layer;
  final bool visible;

  const LayerToggled({
    required this.layer,
    required this.visible,
  });

  @override
  List<Object?> get props => [layer, visible];
}

/// User gesture detected — exit follow mode.
///
/// Dispatched by the widget's onPositionChanged callback when
/// hasGesture is true, matching the monolith's follow-disable pattern.
class UserPanDetected extends MapEvent {
  const UserPanDetected();
}
