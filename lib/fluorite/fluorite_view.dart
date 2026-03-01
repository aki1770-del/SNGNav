/// FluoriteView — PlatformView scaffold for the 3D terrain renderer.
///
/// Currently renders a placeholder with status information. When the native
/// Fluorite renderer becomes available, this will host an AndroidView/UiKitView
/// backed by the Filament 3D engine.
///
/// The widget owns the [FluoriteHostApi] lifecycle:
///   - `initState` -> attempts `initializeScene` (fails gracefully when native
///     renderer is unavailable)
///   - `dispose` -> calls `disposeScene`
///   - Registers as [FluoriteFlutterApi] callback handler
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'fluorite_api.dart';

/// Status of the FluoriteView initialization lifecycle.
enum FluoriteViewStatus {
  /// Waiting to initialize.
  pending,

  /// Scene is initializing (loading DEM, creating GPU context).
  initializing,

  /// Scene is ready — 3D rendering active.
  ready,

  /// Initialization failed — showing fallback or error info.
  unavailable,
}

/// PlatformView scaffold for the Fluorite 3D terrain renderer.
///
/// Currently this widget renders a placeholder showing the view status.
/// When the native renderer is available, it will host a native PlatformView
/// (AndroidView / UiKitView) connected to the Filament engine via Pigeon.
class FluoriteView extends StatefulWidget {
  const FluoriteView({
    super.key,
    this.hostApi,
    this.config,
    this.onStatusChanged,
    this.placeholder,
  });

  /// Host API implementation. Defaults to [NotImplementedHostApi].
  final FluoriteHostApi? hostApi;

  /// Scene configuration. Uses defaults if not provided.
  final SceneConfig? config;

  /// Called when the view status changes.
  final ValueChanged<FluoriteViewStatus>? onStatusChanged;

  /// Custom placeholder widget shown when 3D is unavailable.
  /// If null, a default status card is rendered.
  final Widget? placeholder;

  @override
  State<FluoriteView> createState() => FluoriteViewState();
}

/// Exposed state for testing and programmatic access.
class FluoriteViewState extends State<FluoriteView>
    implements FluoriteFlutterApi {
  FluoriteViewStatus _status = FluoriteViewStatus.pending;
  SceneInfo? _sceneInfo;
  String? _errorMessage;

  late final FluoriteHostApi _hostApi;

  /// Current view status.
  FluoriteViewStatus get status => _status;

  /// Scene info (available when status is [FluoriteViewStatus.ready]).
  SceneInfo? get sceneInfo => _sceneInfo;

  /// Error message (available when status is [FluoriteViewStatus.unavailable]).
  String? get errorMessage => _errorMessage;

  @override
  void initState() {
    super.initState();
    _hostApi = widget.hostApi ?? const NotImplementedHostApi();
    _initializeScene();
  }

  Future<void> _initializeScene() async {
    _setStatus(FluoriteViewStatus.initializing);

    try {
      final config = widget.config ??
          const SceneConfig(demAssetPath: 'assets/dem/aichi_30m.tif');
      final info = await _hostApi.initializeScene(config);
      if (!mounted) return;
      _sceneInfo = info;
      _setStatus(FluoriteViewStatus.ready);
    } on UnimplementedError catch (e) {
      // Expected when native renderer is not available.
      if (!mounted) return;
      _errorMessage = e.message;
      _setStatus(FluoriteViewStatus.unavailable);
    } catch (e) {
      // Unexpected error — GPU failure, missing asset, etc.
      if (!mounted) return;
      _errorMessage = e.toString();
      _setStatus(FluoriteViewStatus.unavailable);
    }
  }

  void _setStatus(FluoriteViewStatus newStatus) {
    if (!mounted) return;
    setState(() => _status = newStatus);
    widget.onStatusChanged?.call(newStatus);
  }

  @override
  void dispose() {
    // Best-effort cleanup — ignore errors if scene was never initialized.
    _hostApi.disposeScene().catchError((_) {});
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // FluoriteFlutterApi callbacks (C++ -> Dart, active when native renderer is available)
  // -------------------------------------------------------------------------

  @override
  void onSceneReady(SceneInfo info) {
    if (!mounted) return;
    setState(() {
      _sceneInfo = info;
      _status = FluoriteViewStatus.ready;
    });
  }

  @override
  void onEntityTapped(int entityId, LatLng position) {
    // TODO: forward to a callback or BLoC event when native renderer is wired.
    debugPrint('FluoriteView: entity $entityId tapped at $position');
  }

  @override
  void onFrameStats({
    required double frameTimeMs,
    required double gpuMemoryMb,
    required int entityCount,
  }) {
    // Update performance overlay or analytics when native renderer is wired.
    if (!mounted) return;
    setState(() {
      _sceneInfo = SceneInfo(
        isReady: true,
        entityCount: entityCount,
        frameTimeMs: frameTimeMs,
        gpuMemoryMb: gpuMemoryMb,
      );
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      FluoriteViewStatus.pending ||
      FluoriteViewStatus.initializing =>
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Initializing 3D scene...'),
            ],
          ),
        ),
      FluoriteViewStatus.ready => _buildPlatformView(),
      FluoriteViewStatus.unavailable => widget.placeholder ?? _buildFallback(),
    };
  }

  /// Replace with AndroidView / UiKitView hosting Filament surface when available.
  Widget _buildPlatformView() {
    // Scene reported ready (mock scenario) — show info.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_in_ar, size: 48, color: Colors.green),
          const SizedBox(height: 8),
          const Text('Fluorite 3D Scene Active'),
          if (_sceneInfo != null) ...[
            const SizedBox(height: 4),
            Text(
              'Entities: ${_sceneInfo!.entityCount} · '
              'Frame: ${_sceneInfo!.frameTimeMs.toStringAsFixed(1)}ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Default fallback when 3D is unavailable.
  Widget _buildFallback() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terrain, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                '3D Renderer Unavailable',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Using 2D map fallback',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
