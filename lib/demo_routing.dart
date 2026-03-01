/// Routing Demo — mock engine → RoutingBloc → route display.
///
/// Run: flutter run -d linux -t lib/demo_routing.dart
///
/// Shows the RoutingBloc 4-state lifecycle (idle → loading → routeActive → idle)
/// with a mock engine. Three preset destinations around the Nagoya area.
/// Displays route summary, maneuver list with icons, and engine info.
///
/// Demonstrates the RoutingBloc lifecycle with mock and real routing engines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import 'bloc/routing_bloc.dart';
import 'bloc/routing_event.dart';
import 'bloc/routing_state.dart';
import 'models/route_result.dart';
import 'providers/routing_engine.dart';
import 'widgets/maneuver_icons.dart';

// ---------------------------------------------------------------------------
// Mock routing engine — returns pre-built routes after a simulated delay
// ---------------------------------------------------------------------------

class _MockRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(
        name: 'mock',
        version: '1.0',
        queryLatency: Duration(milliseconds: 800),
      );

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    // Simulate engine computation
    await Future<void>.delayed(const Duration(milliseconds: 800));

    return _buildRoute(request.origin, request.destination);
  }

  RouteResult _buildRoute(LatLng origin, LatLng dest) {
    // Simple straight-line with synthesized maneuvers
    final distance = const Distance();
    final totalKm = distance.as(LengthUnit.Kilometer, origin, dest);
    final bearing = distance.bearing(origin, dest);

    // Generate intermediate points
    final points = <LatLng>[origin];
    for (var i = 1; i < 5; i++) {
      final frac = i / 5;
      points.add(LatLng(
        origin.latitude + (dest.latitude - origin.latitude) * frac,
        origin.longitude + (dest.longitude - origin.longitude) * frac,
      ));
    }
    points.add(dest);

    // Generate maneuvers
    final maneuvers = [
      RouteManeuver(
        index: 0,
        instruction: 'Depart — head ${_bearingLabel(bearing)}',
        type: 'depart',
        lengthKm: totalKm * 0.15,
        timeSeconds: totalKm * 0.15 * 60,
        position: origin,
      ),
      RouteManeuver(
        index: 1,
        instruction: 'Continue on main road',
        type: 'straight',
        lengthKm: totalKm * 0.25,
        timeSeconds: totalKm * 0.25 * 55,
        position: points[1],
      ),
      RouteManeuver(
        index: 2,
        instruction: 'Turn right at intersection',
        type: 'right',
        lengthKm: totalKm * 0.20,
        timeSeconds: totalKm * 0.20 * 50,
        position: points[2],
      ),
      RouteManeuver(
        index: 3,
        instruction: 'Merge onto expressway',
        type: 'merge',
        lengthKm: totalKm * 0.25,
        timeSeconds: totalKm * 0.25 * 45,
        position: points[3],
      ),
      RouteManeuver(
        index: 4,
        instruction: 'Take exit ramp',
        type: 'ramp_right',
        lengthKm: totalKm * 0.10,
        timeSeconds: totalKm * 0.10 * 60,
        position: points[4],
      ),
      RouteManeuver(
        index: 5,
        instruction: 'Arrive at destination',
        type: 'arrive',
        lengthKm: totalKm * 0.05,
        timeSeconds: totalKm * 0.05 * 40,
        position: dest,
      ),
    ];

    final totalTime = maneuvers.fold<double>(
        0, (sum, m) => sum + m.timeSeconds);

    return RouteResult(
      shape: points,
      maneuvers: maneuvers,
      totalDistanceKm: totalKm,
      totalTimeSeconds: totalTime,
      summary:
          '${totalKm.toStringAsFixed(1)} km — ${(totalTime / 60).toStringAsFixed(0)} min',
      engineInfo: EngineInfo(
        name: 'mock',
        version: '1.0',
        queryLatency: const Duration(milliseconds: 800),
      ),
    );
  }

  String _bearingLabel(double bearing) {
    if (bearing < 45 || bearing >= 315) return 'north';
    if (bearing < 135) return 'east';
    if (bearing < 225) return 'south';
    return 'west';
  }

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Preset destinations around Nagoya
// ---------------------------------------------------------------------------

const _nagoya = LatLng(35.1709, 136.8815);

final _destinations = <({String label, LatLng point, String description})>[
  (
    label: 'Toyota City Hall',
    point: const LatLng(35.0831, 137.1559),
    description: '25 km east via Route 153',
  ),
  (
    label: 'Mikawa Highlands',
    point: const LatLng(35.0700, 137.4000),
    description: '48 km — mountain pass route',
  ),
  (
    label: 'Nagoya Castle',
    point: const LatLng(35.1854, 136.8991),
    description: '2 km — city center',
  ),
];

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

void main() {
  runApp(const RoutingDemoApp());
}

class RoutingDemoApp extends StatelessWidget {
  const RoutingDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNGNav Routing Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
        ),
        useMaterial3: true,
      ),
      home: BlocProvider(
        create: (_) => RoutingBloc(engine: _MockRoutingEngine())
          ..add(const RoutingEngineCheckRequested()),
        child: const RoutingDemoPage(),
      ),
    );
  }
}

class RoutingDemoPage extends StatelessWidget {
  const RoutingDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNGNav — Routing Demo'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Engine status indicator
          BlocBuilder<RoutingBloc, RoutingState>(
            builder: (context, state) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      state.engineAvailable
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 14,
                      color:
                          state.engineAvailable ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.engineAvailable ? 'ENGINE OK' : 'NO ENGINE',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<RoutingBloc, RoutingState>(
        builder: (context, state) {
          return switch (state.status) {
            RoutingStatus.idle => _DestinationPicker(state: state),
            RoutingStatus.loading => const _LoadingView(),
            RoutingStatus.routeActive => _RouteView(state: state),
            RoutingStatus.error => _ErrorView(state: state),
          };
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Idle → pick destination
// ---------------------------------------------------------------------------

class _DestinationPicker extends StatelessWidget {
  final RoutingState state;

  const _DestinationPicker({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Origin
          Card(
            child: ListTile(
              leading: Icon(Icons.my_location,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('Nagoya Station'),
              subtitle: const Text('35.1709°N, 136.8815°E'),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.more_vert, color: Colors.grey, size: 20),
                SizedBox(width: 8),
                Text('Choose destination',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Destination cards
          ...List.generate(_destinations.length, (i) {
            final dest = _destinations[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.place, color: Colors.red),
                title: Text(dest.label),
                subtitle: Text(dest.description),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.read<RoutingBloc>().add(RouteRequested(
                        origin: _nagoya,
                        destination: dest.point,
                        destinationLabel: dest.label,
                      ));
                },
              ),
            );
          }),

          const Spacer(),

          // Status footer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Status: ${state.status.name.toUpperCase()} — '
                    'Engine: ${state.engineAvailable ? "available" : "checking..."}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading → calculating route
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Calculating route...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Mock engine — 800ms simulated latency',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route active → show route details + maneuver list
// ---------------------------------------------------------------------------

class _RouteView extends StatelessWidget {
  final RoutingState state;

  const _RouteView({required this.state});

  @override
  Widget build(BuildContext context) {
    final route = state.route!;
    final theme = Theme.of(context);

    return Column(
      children: [
        // Route summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: theme.colorScheme.primaryContainer,
          child: Row(
            children: [
              Icon(Icons.route,
                  size: 40, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nagoya → ${state.destinationLabel ?? "Destination"}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${route.totalDistanceKm.toStringAsFixed(1)} km — '
                      '${route.eta.inMinutes} min — '
                      '${route.shape.length} shape points',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer
                            .withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
              // Clear route button
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  context
                      .read<RoutingBloc>()
                      .add(const RouteClearRequested());
                },
                tooltip: 'Clear route',
              ),
            ],
          ),
        ),

        // Engine info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.memory, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Engine: ${route.engineInfo.name} v${route.engineInfo.version} — '
                'latency: ${route.engineInfo.queryLatency.inMilliseconds}ms',
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.grey),
              ),
            ],
          ),
        ),

        // Maneuver list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: route.maneuvers.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = route.maneuvers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.primaryContainer,
                  child: Icon(
                    ManeuverIcons.forType(m.type),
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                title: Text(m.instruction),
                subtitle: Text(
                  '${m.lengthKm.toStringAsFixed(1)} km — '
                  '${(m.timeSeconds / 60).toStringAsFixed(0)} min — '
                  'type: ${m.type}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  '#${m.index}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey),
                ),
              );
            },
          ),
        ),

        // Shape points footer
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatChip(
                  label: 'SHAPE PTS', value: '${route.shape.length}'),
              _StatChip(
                  label: 'MANEUVERS',
                  value: '${route.maneuvers.length}'),
              _StatChip(
                  label: 'DISTANCE',
                  value:
                      '${route.totalDistanceKm.toStringAsFixed(1)} km'),
              _StatChip(
                  label: 'ETA',
                  value: '${route.eta.inMinutes} min'),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: const TextStyle(
              fontSize: 9, letterSpacing: 1.2, color: Colors.grey),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error → retry
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final RoutingState state;

  const _ErrorView({required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Routing Error',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            state.errorMessage ?? 'Unknown error',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.red),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              context
                  .read<RoutingBloc>()
                  .add(const RouteClearRequested());
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ],
      ),
    );
  }
}
