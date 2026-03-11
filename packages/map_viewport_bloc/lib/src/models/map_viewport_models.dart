/// Pure Dart models for camera mode, layer types, and layer ordering.
library;

/// Camera mode for the viewport state machine.
enum CameraMode {
  /// Camera follows the driver position.
  follow,

  /// User controls the viewport manually.
  freeLook,

  /// Camera fits an overview of the active route bounds.
  overview,
}

/// Map layers rendered by the Snow Scene stack.
enum MapLayerType {
  /// Base tiles or raster map surface.
  baseTile,

  /// Route line.
  route,

  /// Fleet markers.
  fleet,

  /// Hazard polygons or hazard clusters.
  hazard,

  /// Weather overlay.
  weather,

  /// Safety overlay. Managed by navigation safety, not user toggles.
  safety,
}

/// Canonical Z-order for the six-layer map composition model.
abstract final class MapLayerZ {
  static const int z0 = 0;
  static const int z1 = 1;
  static const int z2 = 2;
  static const int z3 = 3;
  static const int z4 = 4;
  static const int z5 = 5;

  static const int baseTile = z0;
  static const int route = z1;
  static const int fleet = z2;
  static const int hazard = z3;
  static const int weather = z4;
  static const int safety = z5;

  static int of(MapLayerType layer) {
    return switch (layer) {
      MapLayerType.baseTile => baseTile,
      MapLayerType.route => route,
      MapLayerType.fleet => fleet,
      MapLayerType.hazard => hazard,
      MapLayerType.weather => weather,
      MapLayerType.safety => safety,
    };
  }
}

extension MapLayerTypeX on MapLayerType {
  /// User toggles are restricted to Z1 through Z4.
  bool get isUserToggleable {
    return switch (this) {
      MapLayerType.baseTile || MapLayerType.safety => false,
      MapLayerType.route ||
      MapLayerType.fleet ||
      MapLayerType.hazard ||
      MapLayerType.weather => true,
    };
  }

  /// Canonical Z-index for the layer.
  int get zIndex => MapLayerZ.of(this);
}