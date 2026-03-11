import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

const _nagoya = LatLng(35.1709, 136.8815);

final _destinations = <({String label, LatLng point})>[
  (label: 'Toyota City Hall', point: const LatLng(35.0831, 137.1559)),
  (label: 'Mikawa Highlands', point: const LatLng(35.0700, 137.4000)),
  (label: 'Nagoya Castle', point: const LatLng(35.1854, 136.8991)),
];

void main() {
  runApp(const RoutingBlocExampleApp());
}

class RoutingBlocExampleApp extends StatelessWidget {
  const RoutingBlocExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BlocProvider(
        create: (_) => RoutingBloc(engine: _MockRoutingEngine())
          ..add(const RoutingEngineCheckRequested()),
        child: const _ExampleScreen(),
      ),
    );
  }
}

class _ExampleScreen extends StatelessWidget {
  const _ExampleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('routing_bloc example')),
      body: BlocBuilder<RoutingBloc, RoutingState>(
        builder: (context, state) {
          return Column(
            children: [
              RouteProgressBar(
                status: state.hasRoute
                    ? RouteProgressStatus.active
                    : RouteProgressStatus.idle,
                route: state.route,
                destinationLabel: state.destinationLabel,
              ),
              Expanded(
                child: switch (state.status) {
                  RoutingStatus.idle => _DestinationList(state: state),
                  RoutingStatus.loading => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  RoutingStatus.routeActive => _RouteDetails(state: state),
                  RoutingStatus.error => _ErrorView(state: state),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DestinationList extends StatelessWidget {
  final RoutingState state;

  const _DestinationList({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Engine: ${state.engineAvailable ? 'available' : 'checking...'}',
        ),
        const SizedBox(height: 16),
        for (final dest in _destinations)
          Card(
            child: ListTile(
              title: Text(dest.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.read<RoutingBloc>().add(RouteRequested(
                      origin: _nagoya,
                      destination: dest.point,
                      destinationLabel: dest.label,
                    ));
              },
            ),
          ),
      ],
    );
  }
}

class _RouteDetails extends StatelessWidget {
  final RoutingState state;

  const _RouteDetails({required this.state});

  @override
  Widget build(BuildContext context) {
    final route = state.route!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Summary: ${route.summary}'),
        Text('Engine: ${route.engineInfo.name}'),
        const SizedBox(height: 16),
        for (final maneuver in route.maneuvers)
          ListTile(
            leading: Icon(ManeuverIcons.forType(maneuver.type)),
            title: Text(maneuver.instruction),
            subtitle: Text('${maneuver.lengthKm.toStringAsFixed(1)} km'),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            context.read<RoutingBloc>().add(const RouteClearRequested());
          },
          child: const Text('Clear route'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final RoutingState state;

  const _ErrorView({required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(state.errorMessage ?? 'Unknown routing error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                context.read<RoutingBloc>().add(const RouteClearRequested());
              },
              child: const Text('Back to idle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(name: 'mock', version: '1.0');

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return RouteResult(
      shape: [request.origin, request.destination],
      maneuvers: [
        RouteManeuver(
          index: 0,
          instruction: 'Depart',
          type: 'depart',
          lengthKm: 10,
          timeSeconds: 600,
          position: request.origin,
        ),
        RouteManeuver(
          index: 1,
          instruction: 'Arrive at destination',
          type: 'arrive',
          lengthKm: 0,
          timeSeconds: 0,
          position: request.destination,
        ),
      ],
      totalDistanceKm: 10,
      totalTimeSeconds: 600,
      summary: '10 km, 10 min',
      engineInfo: const EngineInfo(
        name: 'mock',
        version: '1.0',
        queryLatency: Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}