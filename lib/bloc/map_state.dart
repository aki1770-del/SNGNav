/// Map state — declarative viewport + camera mode + layer visibility.
///
/// MapBloc emits *what the map should show*. The widget reads MapState
/// and applies it to MapController. MapBloc is testable without a
/// Flutter widget tree.
///
/// State transitions:
///   loading → ready (map initialized)
///   ready → ready (center/zoom/mode/layer changes stay in ready)
///   any → error (map error)
///
/// Covers viewport, camera mode, and layer visibility.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// Map rendering status.
enum MapStatus {
  /// Map is loading (initial state).
  loading,

  /// Map is ready for interaction.
  ready,

  /// Map error (tile load failure, etc.).
  error,
}

/// Camera mode — determines how the viewport follows the vehicle.
///
/// Follow, FreeLook, Overview.
enum CameraMode {
  /// Camera tracks GPS position. Equivalent to monolith's _followMode = true.
  follow,

  /// User controls viewport freely. Equivalent to _followMode = false.
  freeLook,

  /// Viewport fits to route bounds. Used after route calculation.
  overview,
}

/// Map layer types for visibility toggling.
///
/// Each layer corresponds to a flutter_map child rendered conditionally.
/// Default visible: {route}. Others activate as features are built.
enum MapLayerType {
  /// Route polyline layer.
  route,

  /// Weather overlay.
  weather,

  /// Safety indicators.
  safety,

  /// Fleet data visualization.
  fleet,
}

class MapState extends Equatable {
  final MapStatus status;
  final LatLng center;
  final double zoom;
  final CameraMode cameraMode;

  /// Non-null when overview mode is requested — widget applies via fitCamera.
  /// Cleared after the widget consumes it (widget sets back to null via event).
  final LatLng? fitBoundsSw;
  final LatLng? fitBoundsNe;

  final Set<MapLayerType> visibleLayers;
  final String? errorMessage;

  const MapState({
    required this.status,
    required this.center,
    required this.zoom,
    this.cameraMode = CameraMode.freeLook,
    this.fitBoundsSw,
    this.fitBoundsNe,
    this.visibleLayers = const {MapLayerType.route},
    this.errorMessage,
  });

  /// Default initial state — loading, centered on Nagoya.
  const MapState.loading()
      : status = MapStatus.loading,
        center = const LatLng(35.1709, 136.8815),
        zoom = 12.0,
        cameraMode = CameraMode.freeLook,
        fitBoundsSw = null,
        fitBoundsNe = null,
        visibleLayers = const {MapLayerType.route},
        errorMessage = null;

  // ---------------------------------------------------------------------------
  // Convenience getters
  // ---------------------------------------------------------------------------

  /// True when camera is tracking GPS position.
  bool get isFollowing => cameraMode == CameraMode.follow;

  /// True when map is ready for interaction.
  bool get isReady => status == MapStatus.ready;

  /// True when fit-to-bounds has been requested (widget should consume).
  bool get hasFitBounds => fitBoundsSw != null && fitBoundsNe != null;

  /// Whether a specific layer is visible.
  bool isLayerVisible(MapLayerType layer) => visibleLayers.contains(layer);

  MapState copyWith({
    MapStatus? status,
    LatLng? center,
    double? zoom,
    CameraMode? cameraMode,
    LatLng? fitBoundsSw,
    LatLng? fitBoundsNe,
    Set<MapLayerType>? visibleLayers,
    String? errorMessage,
    bool clearFitBounds = false,
  }) {
    return MapState(
      status: status ?? this.status,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
      cameraMode: cameraMode ?? this.cameraMode,
      fitBoundsSw: clearFitBounds ? null : (fitBoundsSw ?? this.fitBoundsSw),
      fitBoundsNe: clearFitBounds ? null : (fitBoundsNe ?? this.fitBoundsNe),
      visibleLayers: visibleLayers ?? this.visibleLayers,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        center,
        zoom,
        cameraMode,
        fitBoundsSw,
        fitBoundsNe,
        visibleLayers,
        errorMessage,
      ];

  @override
  String toString() =>
      'MapState($status, $cameraMode, zoom=$zoom, '
      'layers=${visibleLayers.map((l) => l.name).join(",")})';
}
