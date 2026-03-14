import 'dart:async';
import 'dart:io';

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:offline_tiles/offline_tiles.dart' as offline_tiles;
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

const _origin = LatLng(35.1709, 136.8815);
const _destination = LatLng(35.0700, 137.4000);
const _toyotaCity = LatLng(35.0831, 137.1559);
const _mbtilesPath = '../data/offline_tiles.mbtiles';

final _demoRoute = RouteResult(
  shape: const [
    LatLng(35.1709, 136.8815),
    LatLng(35.1680, 136.9100),
    LatLng(35.1450, 136.9600),
    LatLng(35.1200, 137.0100),
    LatLng(35.0831, 137.1559),
    LatLng(35.0600, 137.2500),
    LatLng(35.0500, 137.3200),
    LatLng(35.0700, 137.4000),
  ],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Depart Nagoya Station via Route 153 East',
      type: 'depart',
      lengthKm: 2.1,
      timeSeconds: 180,
      position: LatLng(35.1709, 136.8815),
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Continue east on Route 153',
      type: 'straight',
      lengthKm: 4.5,
      timeSeconds: 270,
      position: LatLng(35.1680, 136.9100),
    ),
    RouteManeuver(
      index: 2,
      instruction: 'Bear right toward Toyota',
      type: 'slight_right',
      lengthKm: 5.2,
      timeSeconds: 310,
      position: LatLng(35.1450, 136.9600),
    ),
    RouteManeuver(
      index: 3,
      instruction: 'Continue through Toyota City',
      type: 'straight',
      lengthKm: 6.0,
      timeSeconds: 430,
      position: LatLng(35.1200, 137.0100),
    ),
    RouteManeuver(
      index: 4,
      instruction: 'Turn left toward the mountain road',
      type: 'left',
      lengthKm: 8.0,
      timeSeconds: 690,
      position: LatLng(35.0831, 137.1559),
    ),
    RouteManeuver(
      index: 5,
      instruction: 'Climb toward the summit',
      type: 'straight',
      lengthKm: 5.5,
      timeSeconds: 570,
      position: LatLng(35.0600, 137.2500),
    ),
    RouteManeuver(
      index: 6,
      instruction: 'Descend toward Mikawa Highlands',
      type: 'straight',
      lengthKm: 6.8,
      timeSeconds: 610,
      position: LatLng(35.0500, 137.3200),
    ),
    RouteManeuver(
      index: 7,
      instruction: 'Arrive at Mikawa Highlands',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: LatLng(35.0700, 137.4000),
    ),
  ],
  totalDistanceKm: 38.1,
  totalTimeSeconds: 3060,
  summary: 'Route 153: Nagoya -> Toyota -> Mikawa Highlands',
  engineInfo: EngineInfo(
    name: 'mock',
    version: '0.2.0-example',
    queryLatency: Duration(milliseconds: 24),
  ),
);

void main() {
  runApp(const SngNavExampleApp());
}

class SngNavExampleApp extends StatelessWidget {
  const SngNavExampleApp({super.key, this.homeOverride});

  final Widget? homeOverride;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E6D61)),
        useMaterial3: true,
      ),
      home: homeOverride ??
          MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) => MapBloc()
                  ..add(const MapInitialized(center: _origin, zoom: 9.8)),
              ),
              BlocProvider(
                create: (_) => RoutingBloc(engine: _MockRoutingEngine())
                  ..add(const RoutingEngineCheckRequested()),
              ),
              BlocProvider(create: (_) => NavigationBloc()),
            ],
            child: const ExampleHomePage(),
          ),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  final MapController _mapController = MapController();
  final SimulatedWeatherProvider _weatherProvider =
      SimulatedWeatherProvider(interval: const Duration(seconds: 6));
  StreamSubscription<WeatherCondition>? _weatherSubscription;

  offline_tiles.OfflineTileManager? _offlineTileManager;
  WeatherCondition? _latestWeather;
  String _tileStatus = 'Checking tile source...';
  bool _isOffline = false;
  bool _navigationStarted = false;

  @override
  void initState() {
    super.initState();
    _initTileProvider();
    _startWeather();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoutingBloc>().add(const RouteRequested(
            origin: _origin,
            destination: _destination,
            destinationLabel: 'Mikawa Highlands',
          ));
    });
  }

  Future<void> _initTileProvider() async {
    final file = File(_mbtilesPath);
    if (await file.exists()) {
      final manager = offline_tiles.OfflineTileManager(
        tileSource: offline_tiles.TileSourceType.mbtiles,
        mbtilesPath: _mbtilesPath,
      );
      if (!mounted) {
        manager.dispose();
        return;
      }
      setState(() {
        _offlineTileManager = manager;
        _isOffline = true;
        _tileStatus = 'Offline MBTiles loaded from $_mbtilesPath';
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _tileStatus = 'No MBTiles found, using OpenStreetMap fallback';
    });
  }

  Future<void> _startWeather() async {
    _weatherSubscription = _weatherProvider.conditions.listen((condition) {
      if (!mounted) {
        return;
      }
      setState(() {
        _latestWeather = condition;
      });
      if (condition.isHazardous) {
        context.read<NavigationBloc>().add(
              SafetyAlertReceived(
                message:
                    'Weather: ${condition.precipType.name} ${condition.intensity.name}, visibility ${condition.visibilityMeters.toStringAsFixed(0)} m',
                severity: condition.iceRisk || condition.visibilityMeters < 200
                    ? AlertSeverity.critical
                    : AlertSeverity.warning,
              ),
            );
      }
    });
    await _weatherProvider.startMonitoring();
  }

  void _startNavigation(RouteResult route) {
    if (_navigationStarted) {
      return;
    }
    _navigationStarted = true;
    context.read<NavigationBloc>().add(
          NavigationStarted(
            route: route,
            destinationLabel: 'Mikawa Highlands',
          ),
        );
    context.read<MapBloc>().add(
          FitToBounds(
            southWest: _southWest(route.shape),
            northEast: _northEast(route.shape),
          ),
        );
  }

  void _advanceNavigation() {
    context.read<NavigationBloc>().add(const ManeuverAdvanced());
  }

  void _simulateDeviation() {
    final navBloc = context.read<NavigationBloc>();
    navBloc.add(const RouteDeviationDetected(reason: 'Snow drift on shoulder'));
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      navBloc.add(RerouteCompleted(newRoute: _demoRoute));
    });
  }

  void _applyMapState(MapState state) {
    if (state.hasFitBounds) {
      final bounds = LatLngBounds(state.fitBoundsSw!, state.fitBoundsNe!);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
      );
      return;
    }
    _mapController.move(state.center, state.zoom);
  }

  @override
  void dispose() {
    _weatherSubscription?.cancel();
    _weatherProvider.dispose();
    _offlineTileManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<MapBloc, MapState>(
          listener: (_, state) {
            if (state.isReady) {
              _applyMapState(state);
            }
          },
        ),
        BlocListener<RoutingBloc, RoutingState>(
          listener: (_, state) {
            if (state.hasRoute && state.route != null) {
              _startNavigation(state.route!);
            }
          },
        ),
        BlocListener<NavigationBloc, NavigationState>(
          listener: (_, state) {
            final maneuver = state.currentManeuver;
            if (maneuver != null) {
              context.read<MapBloc>().add(CenterChanged(maneuver.position));
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SNGNav Example'),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  _isOffline ? 'OFFLINE TILES' : 'ONLINE TILES',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final content = [
              Expanded(flex: wide ? 7 : 6, child: _buildMapStack()),
              Expanded(flex: wide ? 4 : 5, child: _buildSidePanel()),
            ];
            return wide
                ? Row(children: content)
                : Column(children: content);
          },
        ),
      ),
    );
  }

  Widget _buildMapStack() {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, mapState) {
        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapState.center,
                initialZoom: mapState.zoom,
                minZoom: 6,
                maxZoom: 16,
                onPositionChanged: (position, hasGesture) {
                  if (!hasGesture) {
                    return;
                  }
                  context.read<MapBloc>().add(const UserPanDetected());
                  context.read<MapBloc>().add(CenterChanged(position.center));
                  context.read<MapBloc>().add(ZoomChanged(position.zoom));
                },
              ),
              children: [
                TileLayer(
                  tileProvider:
                      _offlineTileManager?.tileProvider ?? NetworkTileProvider(),
                  urlTemplate: _offlineTileManager == null
                      ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                      : null,
                  userAgentPackageName: 'com.sngnav.example',
                ),
                BlocBuilder<RoutingBloc, RoutingState>(
                  builder: (context, routingState) {
                    if (!mapState.isLayerVisible(MapLayerType.route) ||
                        !routingState.hasRoute ||
                        routingState.route == null) {
                      return const SizedBox.shrink();
                    }
                    return PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routingState.route!.shape,
                          strokeWidth: 5,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    );
                  },
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _origin,
                      width: 44,
                      height: 44,
                      child: _MarkerBubble(
                        color: Colors.green.shade700,
                        icon: Icons.trip_origin,
                        label: 'Start',
                      ),
                    ),
                    Marker(
                      point: _destination,
                      width: 48,
                      height: 48,
                      child: _MarkerBubble(
                        color: Colors.red.shade700,
                        icon: Icons.place,
                        label: 'Goal',
                      ),
                    ),
                    if (mapState.isLayerVisible(MapLayerType.weather))
                      Marker(
                        point: _toyotaCity,
                        width: 52,
                        height: 52,
                        child: _WeatherMarker(condition: _latestWeather),
                      ),
                  ],
                ),
                const SimpleAttributionWidget(
                  source: Text('© OpenStreetMap contributors'),
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: BlocBuilder<NavigationBloc, NavigationState>(
                builder: (context, navState) {
                  return RouteProgressBar(
                    status: switch (navState.status) {
                      NavigationStatus.idle => RouteProgressStatus.idle,
                      NavigationStatus.navigating => RouteProgressStatus.active,
                      NavigationStatus.deviated => RouteProgressStatus.deviated,
                      NavigationStatus.arrived => RouteProgressStatus.arrived,
                    },
                    route: navState.route,
                    currentManeuverIndex: navState.currentManeuverIndex,
                    destinationLabel: navState.destinationLabel,
                    margin: EdgeInsets.zero,
                  );
                },
              ),
            ),
            const SafetyOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildSidePanel() {
    return ColoredBox(
      color: const Color(0xFFF5F7F4),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _PanelCard(
            title: 'What This Shows',
            child: const Text(
              'A single example app composes offline tiles, viewport state, routing, navigation safety, and weather updates into one runnable flow.',
            ),
          ),
          _PanelCard(
            title: 'Map Controls',
            child: BlocBuilder<MapBloc, MapState>(
              builder: (context, mapState) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => context.read<MapBloc>().add(
                            const CameraModeChanged(CameraMode.follow),
                          ),
                      child: Text(
                        mapState.cameraMode == CameraMode.follow
                            ? 'Following'
                            : 'Follow',
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => context.read<MapBloc>().add(
                            FitToBounds(
                              southWest: _southWest(_demoRoute.shape),
                              northEast: _northEast(_demoRoute.shape),
                            ),
                          ),
                      child: const Text('Overview'),
                    ),
                    for (final layer in MapLayerType.values.where(
                      (layer) => layer.isUserToggleable,
                    ))
                      FilterChip(
                        selected: mapState.isLayerVisible(layer),
                        label: Text(layer.name),
                        onSelected: (selected) => context.read<MapBloc>().add(
                              LayerToggled(layer: layer, visible: selected),
                            ),
                      ),
                  ],
                );
              },
            ),
          ),
          _PanelCard(
            title: 'Navigation Demo',
            child: BlocBuilder<NavigationBloc, NavigationState>(
              builder: (context, navState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: ${navState.status.name}'),
                    const SizedBox(height: 6),
                    Text(
                      navState.currentManeuver?.instruction ?? 'Waiting for route',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: navState.hasRoute ? _advanceNavigation : null,
                          child: const Text('Advance Maneuver'),
                        ),
                        OutlinedButton(
                          onPressed: navState.hasRoute ? _simulateDeviation : null,
                          child: const Text('Simulate Deviation'),
                        ),
                        OutlinedButton(
                          onPressed: navState.hasSafetyAlert
                              ? () => context.read<NavigationBloc>().add(
                                    const SafetyAlertDismissed(),
                                  )
                              : null,
                          child: const Text('Dismiss Alert'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          _PanelCard(
            title: 'Weather Feed',
            child: _WeatherSummary(
              condition: _latestWeather,
              tileStatus: _tileStatus,
            ),
          ),
          _PanelCard(
            title: 'Routing State',
            child: BlocBuilder<RoutingBloc, RoutingState>(
              builder: (context, routingState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Engine available: ${routingState.engineAvailable}'),
                    const SizedBox(height: 6),
                    Text('Status: ${routingState.status.name}'),
                    if (routingState.route != null) ...[
                      const SizedBox(height: 6),
                      Text(routingState.route!.summary),
                      Text(
                        '${routingState.route!.totalDistanceKm.toStringAsFixed(1)} km • ${routingState.route!.eta.inMinutes} min',
                      ),
                    ],
                    if (routingState.errorMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(routingState.errorMessage!),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MockRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => _demoRoute.engineInfo;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _demoRoute;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> dispose() async {}
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MarkerBubble extends StatelessWidget {
  const _MarkerBubble({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMarker extends StatelessWidget {
  const _WeatherMarker({required this.condition});

  final WeatherCondition? condition;

  @override
  Widget build(BuildContext context) {
    final hazardous = condition?.isHazardous ?? false;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hazardous ? Colors.red.shade700 : Colors.blue.shade700,
        shape: BoxShape.circle,
      ),
      child: Icon(
        hazardous ? Icons.ac_unit : Icons.cloud,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

class _WeatherSummary extends StatelessWidget {
  const _WeatherSummary({required this.condition, required this.tileStatus});

  final WeatherCondition? condition;
  final String tileStatus;

  @override
  Widget build(BuildContext context) {
    if (condition == null) {
      return Text(tileStatus);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${condition!.precipType.name} ${condition!.intensity.name}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '${condition!.temperatureCelsius.toStringAsFixed(1)} C • visibility ${condition!.visibilityMeters.toStringAsFixed(0)} m • wind ${condition!.windSpeedKmh.toStringAsFixed(0)} km/h',
        ),
        const SizedBox(height: 6),
        Text(condition!.iceRisk ? 'Ice risk detected' : 'No ice risk'),
        const SizedBox(height: 10),
        Text(tileStatus),
      ],
    );
  }
}

LatLng _southWest(List<LatLng> points) {
  final lat = points.map((point) => point.latitude).reduce((a, b) => a < b ? a : b);
  final lon = points.map((point) => point.longitude).reduce((a, b) => a < b ? a : b);
  return LatLng(lat, lon);
}

LatLng _northEast(List<LatLng> points) {
  final lat = points.map((point) => point.latitude).reduce((a, b) => a > b ? a : b);
  final lon = points.map((point) => point.longitude).reduce((a, b) => a > b ? a : b);
  return LatLng(lat, lon);
}
