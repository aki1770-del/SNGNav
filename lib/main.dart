/// SNGNav Getting Started — Minimal offline map demo.
///
/// This is the shortest path from `git clone` to a working offline map.
/// It demonstrates:
/// - flutter_map rendering on Linux desktop
/// - MBTiles offline tile loading (no network required)
/// - Fallback to online OSM tiles when MBTiles file is absent
///
///
/// Usage:
///   1. Place `offline_tiles.mbtiles` in the `data/` directory
///   2. Run: flutter run -d linux
///   3. See the Chūbu region map (Nagoya / Toyota City area)
library;

import 'dart:io';

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:snow_rendering/snow_rendering.dart';

import 'fluorite/snow_scene_3d_view.dart';

void main() {
  runApp(const SNGNavGettingStarted());
}

class SNGNavGettingStarted extends StatelessWidget {
  const SNGNavGettingStarted({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Getting Started',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
        ),
        useMaterial3: true,
      ),
      home: const OfflineMapPage(),
    );
  }
}

/// Which view fills the main body: the existing top-down 2D map, or the
/// perspective forward-looking 3D snow scene.
enum _ViewMode { map, forward }

class OfflineMapPage extends StatefulWidget {
  const OfflineMapPage({super.key});

  @override
  State<OfflineMapPage> createState() => _OfflineMapPageState();
}

class _OfflineMapPageState extends State<OfflineMapPage> {
  offline_tiles.OfflineTileManager? _offlineTileManager;
  bool _isOffline = false;
  String _statusMessage = 'Initializing...';

  // Default view is the existing 2D map — the toggle is opt-in, the app's
  // default behaviour is unchanged.
  _ViewMode _viewMode = _ViewMode.map;

  // The driving-condition picture fed to the 3D forward-view.
  //
  // NOTE (honest bounds): this is a DEFAULT / SIMULATED assessment, NOT a live
  // feed. This `main.dart` getting-started entrypoint has no weather provider
  // wired (the live DigitrafficWeatherProvider lives in the `driving_weather`
  // package and the full `snow_scene.dart` app, not this minimal demo). Wiring
  // a live/simulated WeatherProvider stream into this assessment is the NEXT
  // step; for now we render a representative "compacted snow, reduced
  // visibility" picture so the forward-view shows a meaningful Snow Scene.
  final DrivingConditionAssessment _assessment =
      DrivingConditionAssessment.fromCondition(
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.moderate,
      temperatureCelsius: -3.0,
      visibilityMeters: 600.0, // reduced — fog wall visible
      windSpeedKmh: 18.0,
      iceRisk: true,
      timestamp: DateTime(2026, 1, 1, 7, 15),
    ),
  );

  // Nagoya Station — default center for Chūbu region tiles
  static const _nagoya = LatLng(35.1709, 136.8815);

  // MBTiles file path — relative to the project directory.
  // The edge developer places her .mbtiles file here.
  static const _mbtilesPath = 'data/offline_tiles.mbtiles';

  @override
  void initState() {
    super.initState();
    _initTileProvider();
  }

  Future<void> _initTileProvider() async {
    final file = File(_mbtilesPath);
    try {
      if (await file.exists()) {
        final manager = offline_tiles.OfflineTileManager(
          tileSource: offline_tiles.TileSourceType.mbtiles,
          mbtilesPath: _mbtilesPath,
        );
        setState(() {
          _offlineTileManager = manager;
          _isOffline = true;
          _statusMessage =
              'Offline — MBTiles loaded (${_formatSize(file.lengthSync())})';
        });
      } else {
        setState(() {
          _offlineTileManager = null;
          _isOffline = false;
          _statusMessage =
              'No MBTiles file at $_mbtilesPath — using online fallback';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'MBTiles error: $e — using online fallback';
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _offlineTileManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Offline Map Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // View-mode toggle: 2D map <-> 3D forward-view. The control lives in
          // the AppBar (idiomatic for a top-level mode switch) and drives the
          // _viewMode field via setState \u2014 matching this page's existing
          // setState-based state pattern (no app-shell BLoC here).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SegmentedButton<_ViewMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                segments: const [
                  ButtonSegment<_ViewMode>(
                    value: _ViewMode.map,
                    icon: Icon(Icons.map_outlined, size: 16),
                    label: Text('2D map'),
                  ),
                  ButtonSegment<_ViewMode>(
                    value: _ViewMode.forward,
                    icon: Icon(Icons.landscape_outlined, size: 16),
                    label: Text('Forward'),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selection) {
                  setState(() => _viewMode = selection.first);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isOffline ? Icons.wifi_off : Icons.wifi,
                    size: 16,
                    color: _isOffline ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOffline ? 'OFFLINE' : 'ONLINE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _isOffline ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: switch (_viewMode) {
        _ViewMode.map => _buildMapView(),
        _ViewMode.forward => _buildForwardView(),
      },
    );
  }

  /// The existing top-down 2D offline map (unchanged behaviour; now extracted
  /// so the body can switch between view modes).
  Widget _buildMapView() {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _nagoya,
            initialZoom: 11,
            minZoom: 6,
            maxZoom: 16,
          ),
          children: [
            TileLayer(
              tileProvider:
                  _offlineTileManager?.tileProvider ?? NetworkTileProvider(),
              urlTemplate: _offlineTileManager == null
                  ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                  : null,
              userAgentPackageName: 'com.sngnav.getting_started',
            ),
            const SimpleAttributionWidget(
              source: Text('\u00a9 OpenStreetMap contributors'),
            ),
          ],
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _statusMessage,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The perspective forward-looking 3D snow scene.
  ///
  /// Honest bounds (see [SnowScene3DView] doc-comment): this is a CPU-projected
  /// still-frame pixel \u2014 no GPU/PBR/lighting; the fog is a linear gradient and
  /// precipitation a deterministic glance-cue sample, not a physics sim. It is
  /// fed by a DEFAULT/SIMULATED [DrivingConditionAssessment] (see [_assessment])
  /// \u2014 live-data wiring is the next step. The advisory chip's text legibility
  /// at small sizes is a known gap.
  Widget _buildForwardView() {
    return Stack(
      children: [
        SnowScene3DView(assessment: _assessment),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Forward-view \u2014 CPU-projected still frame, simulated condition '
              '(live-data wiring is the next step)',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
