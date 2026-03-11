/// Declarative viewport state for the map renderer.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import '../models/map_viewport_models.dart';

const kDefaultMapCenter = LatLng(35.1709, 136.8815);
const double kDefaultFollowZoom = 15.0;
const Set<MapLayerType> kDefaultVisibleLayers = {
  MapLayerType.baseTile,
  MapLayerType.route,
  MapLayerType.fleet,
  MapLayerType.hazard,
  MapLayerType.weather,
  MapLayerType.safety,
};

enum MapStatus {
  loading,
  ready,
  error,
}

class MapState extends Equatable {
  const MapState({
    required this.status,
    required this.center,
    required this.zoom,
    this.cameraMode = CameraMode.follow,
    this.fitBoundsSw,
    this.fitBoundsNe,
    this.visibleLayers = kDefaultVisibleLayers,
    this.errorMessage,
  });

  factory MapState.loading({
    LatLng center = kDefaultMapCenter,
    double zoom = kDefaultFollowZoom,
    Set<MapLayerType> visibleLayers = kDefaultVisibleLayers,
  }) {
    return MapState(
      status: MapStatus.loading,
      center: center,
      zoom: zoom,
      visibleLayers: visibleLayers,
    );
  }

  final MapStatus status;
  final LatLng center;
  final double zoom;
  final CameraMode cameraMode;
  final LatLng? fitBoundsSw;
  final LatLng? fitBoundsNe;
  final Set<MapLayerType> visibleLayers;
  final String? errorMessage;

  bool get isReady => status == MapStatus.ready;
  bool get isFollowing => cameraMode == CameraMode.follow;
  bool get hasFitBounds => fitBoundsSw != null && fitBoundsNe != null;

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
      errorMessage: errorMessage ?? this.errorMessage,
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
  String toString() {
    return 'MapState($status, $cameraMode, zoom=$zoom, '
        'layers=${visibleLayers.map((layer) => layer.name).join(",")})';
  }
}