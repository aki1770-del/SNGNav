/// Navigation Demo — simulated GPS track + NavigationBloc + widgets.
///
/// Run: flutter run -d linux -t lib/demo_navigation.dart
///
/// Simulates a drive along the Nagoya → Toyota → Mikawa Highlands route
/// with 8 maneuvers. Advances every 4 seconds. Shows:
///   - SpeedDisplay with GPS quality indicator
///   - RouteProgressBar with maneuver icons + ETA
///   - SafetyOverlay with simulated alerts at key points
///
/// Demonstrates turn-by-turn navigation with GPS tracking and safety alerts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';

import 'bloc/location_bloc.dart';
import 'bloc/location_event.dart';
import 'bloc/location_state.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:routing_engine/routing_engine.dart';
import 'widgets/speed_display.dart';

// ---------------------------------------------------------------------------
// Simulated GPS track along the Nagoya mountain pass
// ---------------------------------------------------------------------------

/// 8-point GPS track: Nagoya Station → Route 153 → Toyota → Mikawa Highlands
const _trackPoints = [
  (lat: 35.1709, lon: 136.8815, speed: 0.0, heading: 90.0),   // Nagoya Station
  (lat: 35.1680, lon: 136.9100, speed: 40.0, heading: 95.0),  // Heading east
  (lat: 35.1450, lon: 136.9600, speed: 60.0, heading: 120.0), // Route 153
  (lat: 35.1200, lon: 137.0100, speed: 50.0, heading: 110.0), // Approaching Toyota
  (lat: 35.0831, lon: 137.1559, speed: 45.0, heading: 100.0), // Toyota City
  (lat: 35.0600, lon: 137.2500, speed: 35.0, heading: 80.0),  // Mountain approach
  (lat: 35.0500, lon: 137.3200, speed: 25.0, heading: 70.0),  // Pass summit
  (lat: 35.0700, lon: 137.4000, speed: 40.0, heading: 90.0),  // Mikawa Highlands
];

/// Matching maneuvers for turn-by-turn guidance
final _maneuvers = [
  RouteManeuver(
    index: 0,
    instruction: 'Depart Nagoya Station via Route 153 East',
    type: 'depart',
    lengthKm: 2.1,
    timeSeconds: 180,
    position: const LatLng(35.1709, 136.8815),
  ),
  RouteManeuver(
    index: 1,
    instruction: 'Continue east on Route 153',
    type: 'straight',
    lengthKm: 4.5,
    timeSeconds: 270,
    position: const LatLng(35.1680, 136.9100),
  ),
  RouteManeuver(
    index: 2,
    instruction: 'Bear right onto Route 153 toward Toyota',
    type: 'slight_right',
    lengthKm: 5.2,
    timeSeconds: 310,
    position: const LatLng(35.1450, 136.9600),
  ),
  RouteManeuver(
    index: 3,
    instruction: 'Continue on Route 153 through Toyota City',
    type: 'straight',
    lengthKm: 6.0,
    timeSeconds: 430,
    position: const LatLng(35.1200, 137.0100),
  ),
  RouteManeuver(
    index: 4,
    instruction: 'Turn left at Toyota IC toward mountains',
    type: 'left',
    lengthKm: 8.0,
    timeSeconds: 690,
    position: const LatLng(35.0831, 137.1559),
  ),
  RouteManeuver(
    index: 5,
    instruction: 'Begin mountain ascent — caution: snow possible',
    type: 'straight',
    lengthKm: 5.5,
    timeSeconds: 570,
    position: const LatLng(35.0600, 137.2500),
  ),
  RouteManeuver(
    index: 6,
    instruction: 'Pass summit — descend toward Mikawa Highlands',
    type: 'straight',
    lengthKm: 6.8,
    timeSeconds: 610,
    position: const LatLng(35.0500, 137.3200),
  ),
  RouteManeuver(
    index: 7,
    instruction: 'Arrive at Mikawa Highlands',
    type: 'arrive',
    lengthKm: 0.0,
    timeSeconds: 0,
    position: const LatLng(35.0700, 137.4000),
  ),
];

final _demoRoute = RouteResult(
  shape: _trackPoints.map((p) => LatLng(p.lat, p.lon)).toList(),
  maneuvers: _maneuvers,
  totalDistanceKm: 38.1,
  totalTimeSeconds: 3060,
  summary: 'Route 153: Nagoya → Toyota → Mikawa Highlands',
  engineInfo: const EngineInfo(
    name: 'simulated',
    version: 'demo',
    queryLatency: Duration(milliseconds: 12),
  ),
);

// ---------------------------------------------------------------------------
// Simulated Location Provider — emits positions from the track
// ---------------------------------------------------------------------------

class _SimulatedLocationProvider implements LocationProvider {
  static const _interval = Duration(seconds: 4);
  final _controller = StreamController<GeoPosition>.broadcast();
  Timer? _timer;
  int _index = 0;

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async {
    _index = 0;
    _emit();
    _timer = Timer.periodic(_interval, (_) => _emit());
  }

  void _emit() {
    if (_index >= _trackPoints.length) {
      _index = 0; // loop
    }
    final pt = _trackPoints[_index];
    _controller.add(GeoPosition(
      latitude: pt.lat,
      longitude: pt.lon,
      accuracy: 8.0, // navigation-grade
      speed: pt.speed / 3.6, // km/h → m/s
      heading: pt.heading,
      timestamp: DateTime.now(),
    ));
    _index++;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

void main() {
  runApp(const NavigationDemoApp());
}

class NavigationDemoApp extends StatelessWidget {
  const NavigationDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Navigation Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
        ),
        useMaterial3: true,
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => LocationBloc(
              provider: _SimulatedLocationProvider(),
            )..add(const LocationStartRequested()),
          ),
          BlocProvider(create: (_) => NavigationBloc()),
        ],
        child: const NavigationDemoPage(),
      ),
    );
  }
}

class NavigationDemoPage extends StatefulWidget {
  const NavigationDemoPage({super.key});

  @override
  State<NavigationDemoPage> createState() => _NavigationDemoPageState();
}

class _NavigationDemoPageState extends State<NavigationDemoPage> {
  Timer? _advanceTimer;
  int _step = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Start navigation after a brief delay (let LocationBloc acquire first)
    Future.delayed(const Duration(seconds: 2), _startNavigation);
  }

  void _startNavigation() {
    if (!mounted) return;

    // Dispatch NavigationStarted with the demo route
    context.read<NavigationBloc>().add(NavigationStarted(
          route: _demoRoute,
          destinationLabel: 'Mikawa Highlands',
        ));

    setState(() => _started = true);

    // Auto-advance maneuvers every 4 seconds
    _advanceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      _step++;

      final navBloc = context.read<NavigationBloc>();
      final navState = navBloc.state;

      if (navState.status == NavigationStatus.arrived) {
        _advanceTimer?.cancel();
        return;
      }

      // At step 5 (mountain approach), fire a safety alert
      if (_step == 5) {
        navBloc.add(const SafetyAlertReceived(
          message: 'Snow detected ahead — reduce speed',
          severity: AlertSeverity.warning,
          dismissible: true,
        ));
      }

      // At step 6 (summit), fire a critical alert
      if (_step == 6) {
        navBloc.add(const SafetyAlertReceived(
          message: 'Heavy snow — visibility 150m\nReduce speed immediately',
          severity: AlertSeverity.critical,
          dismissible: false,
        ));
      }

      // At step 7, clear the critical and advance
      if (_step == 7) {
        // Dismiss by sending a new info-level alert
        navBloc.add(const SafetyAlertReceived(
          message: 'Conditions improving',
          severity: AlertSeverity.info,
          dismissible: true,
        ));
      }

      navBloc.add(const ManeuverAdvanced());
    });
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Navigation Demo'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          // Z=0: Main content
          Column(
            children: [
              // Route info header
              _RouteHeader(started: _started),
              const Divider(height: 1),

              // Map placeholder
              const Expanded(child: _MapPlaceholder()),

              // Route progress bar
              BlocBuilder<NavigationBloc, NavigationState>(
                builder: (context, state) {
                  return RouteProgressBar(
                    status: _routeProgressStatus(state.status),
                    route: state.route,
                    currentManeuverIndex: state.currentManeuverIndex,
                    destinationLabel: state.destinationLabel,
                  );
                },
              ),

              // Bottom bar: speed display + info
              const _BottomBar(),
            ],
          ),

          // Z=2: Safety overlay (always in tree — highest z-order)
          const SafetyOverlay(),
        ],
      ),
    );
  }
}

RouteProgressStatus _routeProgressStatus(NavigationStatus status) {
  return switch (status) {
    NavigationStatus.idle => RouteProgressStatus.idle,
    NavigationStatus.navigating => RouteProgressStatus.active,
    NavigationStatus.deviated => RouteProgressStatus.deviated,
    NavigationStatus.arrived => RouteProgressStatus.arrived,
  };
}

class _RouteHeader extends StatelessWidget {
  final bool started;

  const _RouteHeader({required this.started});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            started ? Icons.navigation : Icons.hourglass_top,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  started
                      ? 'Nagoya → Mikawa Highlands'
                      : 'Preparing navigation...',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  started
                      ? '38.1 km via Route 153 — ~51 min'
                      : 'Acquiring GPS...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          BlocBuilder<NavigationBloc, NavigationState>(
            builder: (context, state) {
              return Chip(
                label: Text(
                  state.status.name.toUpperCase(),
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: _statusColor(state.status),
              );
            },
          ),
        ],
      ),
    );
  }

  static Color _statusColor(NavigationStatus status) {
    return switch (status) {
      NavigationStatus.idle => Colors.grey.shade200,
      NavigationStatus.navigating => Colors.green.shade100,
      NavigationStatus.deviated => Colors.amber.shade100,
      NavigationStatus.arrived => Colors.blue.shade100,
    };
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, navState) {
        final maneuver = navState.currentManeuver;
        final progress = navState.progress;

        return Container(
          color: const Color(0xFFE8F0FE),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Big maneuver icon
                if (navState.isNavigating && maneuver != null) ...[
                  Icon(
                    ManeuverIcons.forType(maneuver.type),
                    size: 96,
                    color: Theme.of(context).colorScheme.primary.withAlpha(180),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    maneuver.instruction,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Maneuver ${maneuver.index + 1} of ${_maneuvers.length}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}% complete',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ] else if (navState.status == NavigationStatus.arrived) ...[
                  const Icon(
                    Icons.sports_score,
                    size: 96,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Arrived at Mikawa Highlands',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ] else ...[
                  Icon(
                    Icons.map,
                    size: 96,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Map area — flutter_map renders here in Snow Scene',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Speed display
          const SizedBox(width: 80, child: SpeedDisplay()),
          const SizedBox(width: 16),
          // GPS info
          Expanded(
            child: BlocBuilder<LocationBloc, LocationState>(
              builder: (context, state) {
                final pos = state.position;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'GPS: ${state.quality.name.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _qualityColor(state.quality),
                      ),
                    ),
                    if (pos != null)
                      Text(
                        '${pos.latitude.toStringAsFixed(4)}°N, '
                        '${pos.longitude.toStringAsFixed(4)}°E  '
                        '±${pos.accuracy.toStringAsFixed(0)}m',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: Colors.black54,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // Timestamp
          Text(
            DateTime.now().toString().substring(11, 19),
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  static Color _qualityColor(LocationQuality quality) {
    return switch (quality) {
      LocationQuality.fix => Colors.green,
      LocationQuality.degraded => Colors.amber.shade700,
      LocationQuality.stale => Colors.orange,
      LocationQuality.acquiring => Colors.blue,
      LocationQuality.error => Colors.red,
      LocationQuality.uninitialized => Colors.grey,
    };
  }
}
