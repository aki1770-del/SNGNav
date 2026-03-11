import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';

final _exampleRoute = RouteResult(
  shape: const [LatLng(35.1709, 136.9066), LatLng(34.9551, 137.1771)],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Depart Sakae Station',
      type: 'depart',
      lengthKm: 12,
      timeSeconds: 900,
      position: LatLng(35.1709, 136.9066),
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Arrive Higashiokazaki Station',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: LatLng(34.9551, 137.1771),
    ),
  ],
  totalDistanceKm: 40.0,
  totalTimeSeconds: 2400,
  summary: '40 km, 40 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

void main() {
  runApp(const NavigationSafetyExampleApp());
}

class NavigationSafetyExampleApp extends StatelessWidget {
  const NavigationSafetyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BlocProvider(
        create: (_) => NavigationBloc()..add(NavigationStarted(route: _exampleRoute)),
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
      appBar: AppBar(title: const Text('navigation_safety example')),
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.blueGrey.shade50,
              child: const Center(
                child: Text('Map layer placeholder'),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => context.read<NavigationBloc>().add(
                          const SafetyAlertReceived(
                            message: 'Snow expected in 30 minutes',
                            severity: AlertSeverity.info,
                          ),
                        ),
                    child: const Text('Info'),
                  ),
                  FilledButton(
                    onPressed: () => context.read<NavigationBloc>().add(
                          const SafetyAlertReceived(
                            message: 'Icy road conditions ahead',
                            severity: AlertSeverity.warning,
                          ),
                        ),
                    child: const Text('Warning'),
                  ),
                  FilledButton(
                    onPressed: () => context.read<NavigationBloc>().add(
                          const SafetyAlertReceived(
                            message: 'Visibility zero - pull over immediately',
                            severity: AlertSeverity.critical,
                            dismissible: false,
                          ),
                        ),
                    child: const Text('Critical'),
                  ),
                  OutlinedButton(
                    onPressed: () => context
                        .read<NavigationBloc>()
                        .add(const SafetyAlertDismissed()),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
          ),
          const SafetyOverlay(),
        ],
      ),
    );
  }
}