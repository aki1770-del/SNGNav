/// Map Demo — MapBloc ↔ flutter_map with camera modes + layer toggles.
///
/// Run: flutter run -d linux -t lib/demo_map.dart
///
/// Shows the MapBloc controlling a live flutter_map:
///   - Camera modes: Follow (tracks GPS), FreeLook (user drags), Overview (fit route)
///   - Layer toggles: route, weather, safety, fleet
///   - Simulated GPS position cycling along Nagoya mountain pass
///   - FitToBounds demonstrates route overview
///
/// Demonstrates MapBloc integration with flutter_map for desktop navigation.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'bloc/map_bloc.dart';
import 'bloc/map_event.dart';
import 'bloc/map_state.dart';

// ---------------------------------------------------------------------------
// Simulated GPS track — 6 points along the Nagoya mountain pass
// ---------------------------------------------------------------------------

const _gpsTrack = [
  LatLng(35.1709, 136.8815), // Nagoya Station
  LatLng(35.1450, 136.9600), // Route 153
  LatLng(35.0831, 137.1559), // Toyota City
  LatLng(35.0600, 137.2500), // Mountain approach
  LatLng(35.0500, 137.3200), // Pass summit
  LatLng(35.0700, 137.4000), // Mikawa Highlands
];

// Route bounding box for FitToBounds
const _routeSw = LatLng(35.0400, 136.8700);
const _routeNe = LatLng(35.1800, 137.4200);

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

void main() {
  runApp(const MapDemoApp());
}

class MapDemoApp extends StatelessWidget {
  const MapDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Map Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: BlocProvider(
        create: (_) => MapBloc(),
        child: const MapDemoPage(),
      ),
    );
  }
}

class MapDemoPage extends StatefulWidget {
  const MapDemoPage({super.key});

  @override
  State<MapDemoPage> createState() => _MapDemoPageState();
}

class _MapDemoPageState extends State<MapDemoPage> {
  final MapController _mapController = MapController();
  Timer? _gpsTimer;
  int _gpsIndex = 0;
  LatLng _currentPosition = _gpsTrack[0];

  @override
  void initState() {
    super.initState();

    // Initialize the map after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapBloc>().add(const MapInitialized(
            center: LatLng(35.1709, 136.8815),
            zoom: 11,
          ));
    });

    // Simulate GPS updates every 3 seconds
    _gpsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _gpsIndex = (_gpsIndex + 1) % _gpsTrack.length;
      setState(() {
        _currentPosition = _gpsTrack[_gpsIndex];
      });

      final mapBloc = context.read<MapBloc>();
      if (mapBloc.state.cameraMode == CameraMode.follow) {
        mapBloc.add(CenterChanged(_currentPosition));
      }
    });
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Map Demo'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: BlocConsumer<MapBloc, MapState>(
        listenWhen: (prev, curr) =>
            prev.center != curr.center ||
            prev.zoom != curr.zoom ||
            prev.hasFitBounds != curr.hasFitBounds,
        listener: (context, state) {
          // Reconcile MapState → MapController
          if (state.hasFitBounds) {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds(state.fitBoundsSw!, state.fitBoundsNe!),
                padding: const EdgeInsets.all(48),
              ),
            );
          } else if (state.cameraMode == CameraMode.follow) {
            _mapController.move(state.center, _mapController.camera.zoom);
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              // The map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: state.center,
                  initialZoom: state.zoom,
                  onPositionChanged: (pos, hasGesture) {
                    if (hasGesture) {
                      context.read<MapBloc>().add(const UserPanDetected());
                    }
                  },
                ),
                children: [
                  // Base tiles (online OSM)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.sngnav.map_demo',
                  ),

                  // Route layer
                  if (state.isLayerVisible(MapLayerType.route))
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _gpsTrack,
                          strokeWidth: 4,
                          color: Colors.blue,
                        ),
                      ],
                    ),

                  // Weather layer (translucent overlay)
                  if (state.isLayerVisible(MapLayerType.weather))
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: const [
                            LatLng(35.10, 137.15),
                            LatLng(35.10, 137.45),
                            LatLng(35.00, 137.45),
                            LatLng(35.00, 137.15),
                          ],
                          color: Colors.blue.withAlpha(40),
                          borderColor: Colors.blue.withAlpha(100),
                          borderStrokeWidth: 2,
                          label: 'Snow Zone',
                          labelStyle: const TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                  // Safety layer (hazard markers)
                  if (state.isLayerVisible(MapLayerType.safety))
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: const LatLng(35.0500, 137.3200),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.warning,
                              color: Colors.red, size: 32),
                        ),
                        Marker(
                          point: const LatLng(35.0600, 137.2500),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.ac_unit,
                              color: Colors.blue, size: 28),
                        ),
                      ],
                    ),

                  // Fleet layer (other vehicles)
                  if (state.isLayerVisible(MapLayerType.fleet))
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: const LatLng(35.0700, 137.1800),
                          width: 32,
                          height: 32,
                          child: const Icon(Icons.directions_car,
                              color: Colors.green, size: 24),
                        ),
                        Marker(
                          point: const LatLng(35.0550, 137.2800),
                          width: 32,
                          height: 32,
                          child: const Icon(Icons.directions_car,
                              color: Colors.green, size: 24),
                        ),
                        Marker(
                          point: const LatLng(35.0900, 137.0500),
                          width: 32,
                          height: 32,
                          child: const Icon(Icons.directions_car,
                              color: Colors.orange, size: 24),
                        ),
                      ],
                    ),

                  // Current position marker
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPosition,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Attribution
                  const SimpleAttributionWidget(
                    source: Text('\u00a9 OpenStreetMap contributors'),
                  ),
                ],
              ),

              // Camera mode controls (top-right)
              Positioned(
                top: 16,
                right: 16,
                child: _CameraModePanel(state: state),
              ),

              // Layer toggles (top-left)
              Positioned(
                top: 16,
                left: 16,
                child: _LayerPanel(state: state),
              ),

              // State info bar (bottom)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _StateInfoBar(
                    state: state, position: _currentPosition),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera mode panel
// ---------------------------------------------------------------------------

class _CameraModePanel extends StatelessWidget {
  final MapState state;

  const _CameraModePanel({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Camera',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _CameraButton(
              icon: Icons.my_location,
              label: 'Follow',
              active: state.cameraMode == CameraMode.follow,
              onTap: () => context
                  .read<MapBloc>()
                  .add(const CameraModeChanged(CameraMode.follow)),
            ),
            _CameraButton(
              icon: Icons.pan_tool,
              label: 'Free',
              active: state.cameraMode == CameraMode.freeLook,
              onTap: () => context
                  .read<MapBloc>()
                  .add(const CameraModeChanged(CameraMode.freeLook)),
            ),
            _CameraButton(
              icon: Icons.zoom_out_map,
              label: 'Overview',
              active: state.cameraMode == CameraMode.overview,
              onTap: () => context.read<MapBloc>().add(const FitToBounds(
                    southWest: _routeSw,
                    northEast: _routeNe,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CameraButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? Colors.blue : Colors.grey),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? Colors.blue : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layer toggle panel
// ---------------------------------------------------------------------------

class _LayerPanel extends StatelessWidget {
  final MapState state;

  const _LayerPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Layers',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final layer in MapLayerType.values)
              _LayerToggle(
                layer: layer,
                visible: state.isLayerVisible(layer),
              ),
          ],
        ),
      ),
    );
  }
}

class _LayerToggle extends StatelessWidget {
  final MapLayerType layer;
  final bool visible;

  const _LayerToggle({required this.layer, required this.visible});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.read<MapBloc>().add(LayerToggled(
            layer: layer,
            visible: !visible,
          )),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              visible ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: visible ? _layerColor(layer) : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              layer.name,
              style: TextStyle(
                fontSize: 11,
                color: visible ? Colors.black87 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _layerColor(MapLayerType layer) {
    return switch (layer) {
      MapLayerType.route => Colors.blue,
      MapLayerType.weather => Colors.cyan,
      MapLayerType.safety => Colors.red,
      MapLayerType.fleet => Colors.green,
    };
  }
}

// ---------------------------------------------------------------------------
// State info bar
// ---------------------------------------------------------------------------

class _StateInfoBar extends StatelessWidget {
  final MapState state;
  final LatLng position;

  const _StateInfoBar({required this.state, required this.position});

  @override
  Widget build(BuildContext context) {
    final layers =
        state.visibleLayers.map((l) => l.name).join(', ');

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Status: ${state.status.name} | '
              'Camera: ${state.cameraMode.name} | '
              'Zoom: ${state.zoom.toStringAsFixed(1)} | '
              'Layers: [$layers]',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Text(
            '${position.latitude.toStringAsFixed(4)}°N, '
            '${position.longitude.toStringAsFixed(4)}°E',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
