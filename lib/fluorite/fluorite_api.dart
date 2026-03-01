/// Fluorite Pigeon API stubs — Dart-side contract for 3D renderer integration.
///
/// These abstract classes define the same interface that `pigeon` codegen
/// would generate from a `.pigeons` schema. Since the C++ side (Filament
/// renderer) is not yet available, these serve as:
///
///   1. Compile-time contract — edge developer sees the exact API surface
///   2. Test target — FluoriteView can be tested against mock implementations
///   3. Drop-in replacement — when the native renderer is available, replace
///      stubs with codegen
///
/// API surface:
///   - `FluoriteHostApi` (Dart -> C++): scene lifecycle, entity CRUD, camera
///   - `FluoriteFlutterApi` (C++ -> Dart): callbacks for scene events
///   - Data classes: SceneConfig, SceneInfo, RouteStyle, FluoriteCameraMode
library;

import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// Data classes — Pigeon @HostApi/@FlutterApi message types
// ---------------------------------------------------------------------------

/// Configuration for initializing the Fluorite 3D scene.
class SceneConfig {
  const SceneConfig({
    required this.demAssetPath,
    this.initialCenter = const LatLng(35.1709, 136.8815),
    this.initialZoom = 10.0,
    this.enablePbr = true,
    this.maxTextureResolution = 2048,
  });

  /// Path to the DEM (Digital Elevation Model) asset.
  final String demAssetPath;

  /// Initial camera center (WGS84).
  final LatLng initialCenter;

  /// Initial zoom level (0–18 range, mapped to camera altitude).
  final double initialZoom;

  /// Enable Filament PBR materials (snow/ice surface rendering).
  final bool enablePbr;

  /// Maximum texture resolution for terrain tiles.
  final int maxTextureResolution;
}

/// Scene status information returned from the native side.
class SceneInfo {
  const SceneInfo({
    required this.isReady,
    this.entityCount = 0,
    this.frameTimeMs = 0.0,
    this.gpuMemoryMb = 0.0,
  });

  /// Whether the scene has completed initialization.
  final bool isReady;

  /// Number of active ECS entities in the scene.
  final int entityCount;

  /// Last frame render time in milliseconds.
  final double frameTimeMs;

  /// Current GPU memory usage in megabytes.
  final double gpuMemoryMb;
}

/// Camera mode for the 3D scene.
enum FluoriteCameraMode {
  /// Free orbit — user controls camera via gestures.
  freeOrbit,

  /// Follow vehicle — camera tracks the driver position.
  followVehicle,

  /// Bird's-eye — top-down view (2D-like).
  birdsEye,
}

/// Visual styling for a rendered route in the 3D scene.
class RouteStyle {
  const RouteStyle({
    this.colorHex = 0xFF2196F3,
    this.widthMeters = 8.0,
    this.elevationOffsetMeters = 1.0,
    this.dashPattern,
  });

  /// Route color as ARGB hex (default: Material Blue).
  final int colorHex;

  /// Route width in world-space meters.
  final double widthMeters;

  /// Vertical offset above terrain surface.
  final double elevationOffsetMeters;

  /// Optional dash pattern (null = solid line).
  final List<double>? dashPattern;
}

// ---------------------------------------------------------------------------
// FluoriteHostApi — Dart → C++ (Platform Channel)
// ---------------------------------------------------------------------------

/// Host API contract: methods the Dart side calls on the C++ renderer.
///
/// When the native renderer is available, `pigeon` codegen generates a
/// concrete implementation that marshals these calls over a platform channel
/// to the Filament engine. Until then, `FluoriteView` uses a
/// `NotImplementedHostApi` stub.
abstract class FluoriteHostApi {
  /// Initialize the 3D scene with the given configuration.
  ///
  /// Returns a [SceneInfo] once the scene is ready, or throws if
  /// initialization fails (missing DEM asset, GPU not supported, etc.).
  Future<SceneInfo> initializeScene(SceneConfig config);

  /// Dispose the 3D scene and release all GPU resources.
  Future<void> disposeScene();

  /// Create an ECS entity at the given position.
  ///
  /// Returns the entity ID (int handle).
  Future<int> createEntity({
    required String type,
    required LatLng position,
    Map<String, dynamic>? properties,
  });

  /// Destroy an ECS entity by ID.
  Future<void> destroyEntity(int entityId);

  /// Update the position of an existing entity.
  Future<void> updateEntityPosition({
    required int entityId,
    required LatLng position,
    double? heading,
  });

  /// Set the camera mode.
  Future<void> setCameraMode(FluoriteCameraMode mode);

  /// Set route geometry for 3D rendering.
  ///
  /// The route is draped on the terrain mesh with the given style.
  Future<void> setRouteGeometry({
    required List<LatLng> points,
    RouteStyle style = const RouteStyle(),
  });

  /// Clear the currently displayed route.
  Future<void> clearRoute();

  /// Query current scene info (entity count, frame time, memory).
  Future<SceneInfo> getSceneInfo();
}

// ---------------------------------------------------------------------------
// FluoriteFlutterApi — C++ → Dart (Callback Channel)
// ---------------------------------------------------------------------------

/// Flutter API contract: callbacks the C++ renderer invokes on Dart.
///
/// When the native renderer is available, `pigeon` codegen generates a
/// registration mechanism. The `FluoriteView` widget registers itself as
/// the callback handler.
abstract class FluoriteFlutterApi {
  /// Called when the 3D scene has finished initializing.
  void onSceneReady(SceneInfo info);

  /// Called when the user taps an entity in the 3D scene.
  void onEntityTapped(int entityId, LatLng position);

  /// Called each frame with performance statistics.
  void onFrameStats({
    required double frameTimeMs,
    required double gpuMemoryMb,
    required int entityCount,
  });
}

// ---------------------------------------------------------------------------
// NotImplementedHostApi — Stub (native renderer not yet available)
// ---------------------------------------------------------------------------

/// Stub implementation that throws [UnimplementedError] for every method.
///
/// Used by `FluoriteView` when the native renderer is not available. Every
/// call produces a clear error message directing the developer to the
/// integration guide.
class NotImplementedHostApi implements FluoriteHostApi {
  const NotImplementedHostApi();

  static const _msg = 'Fluorite native renderer not available. '
      'Stub — see CONTRIBUTING.md for integration guidance.';

  @override
  Future<SceneInfo> initializeScene(SceneConfig config) =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<void> disposeScene() =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<int> createEntity({
    required String type,
    required LatLng position,
    Map<String, dynamic>? properties,
  }) =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<void> destroyEntity(int entityId) =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<void> updateEntityPosition({
    required int entityId,
    required LatLng position,
    double? heading,
  }) =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<void> setCameraMode(FluoriteCameraMode mode) =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<void> setRouteGeometry({
    required List<LatLng> points,
    RouteStyle style = const RouteStyle(),
  }) =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<void> clearRoute() =>
      Future.error(UnimplementedError(_msg));

  @override
  Future<SceneInfo> getSceneInfo() =>
      Future.error(UnimplementedError(_msg));
}
