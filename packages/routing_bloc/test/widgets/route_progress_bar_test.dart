library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);

final _route = NavigationRoute(
  shape: const [_nagoya, _toyota],
  maneuvers: const [
    NavigationManeuver(
      index: 0,
      instruction: 'Head east',
      type: 'depart',
      lengthKm: 12.5,
      timeSeconds: 720,
      position: _nagoya,
    ),
    NavigationManeuver(
      index: 1,
      instruction: 'Arrive at Toyota',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 25.7,
  totalTimeSeconds: 1830,
  summary: '25.7 km, 31 min',
);

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('idle renders nothing', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RouteProgressBar(status: RouteProgressStatus.idle),
      ),
    );

    expect(find.byType(Card), findsNothing);
    expect(find.text('Rerouting...'), findsNothing);
  });

  testWidgets('active route renders instruction eta and distance', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RouteProgressBar(
          status: RouteProgressStatus.active,
          route: _route,
        ),
      ),
    );

    expect(find.text('Head east'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('25.7 km'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('deviated renders rerouting card', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RouteProgressBar(status: RouteProgressStatus.deviated),
      ),
    );

    expect(find.text('Rerouting...'), findsOneWidget);
    expect(find.byIcon(Icons.wrong_location), findsOneWidget);
  });

  testWidgets('arrived renders destination label', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RouteProgressBar(
          status: RouteProgressStatus.arrived,
          destinationLabel: 'Toyota HQ',
        ),
      ),
    );

    expect(find.text('Arrived at Toyota HQ'), findsOneWidget);
  });

  testWidgets('active route uses maneuver icon mapping', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RouteProgressBar(
          status: RouteProgressStatus.active,
          route: _route,
        ),
      ),
    );

    expect(find.byIcon(Icons.flag), findsOneWidget);
  });

  testWidgets('arrived sets progress indicator complete when active replaced', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RouteProgressBar(
          status: RouteProgressStatus.active,
          route: _route,
          currentManeuverIndex: 1,
        ),
      ),
    );

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.5);
  });
}
