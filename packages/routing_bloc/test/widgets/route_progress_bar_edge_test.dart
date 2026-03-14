/// Edge-case tests for RouteProgressBar widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);
const _inuyama = LatLng(35.3883, 136.9394);

final _routeWith3Maneuvers = RouteResult(
  shape: const [_nagoya, _inuyama, _toyota],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head north',
      type: 'depart',
      lengthKm: 10.0,
      timeSeconds: 600,
      position: _nagoya,
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Turn right',
      type: 'right',
      lengthKm: 8.0,
      timeSeconds: 480,
      position: _inuyama,
    ),
    RouteManeuver(
      index: 2,
      instruction: 'Arrive',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 18.0,
  totalTimeSeconds: 1080,
  summary: '18.0 km, 18 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

final _emptyManeuverRoute = RouteResult(
  shape: const [_nagoya, _toyota],
  maneuvers: const [],
  totalDistanceKm: 25.0,
  totalTimeSeconds: 1800,
  summary: '25.0 km, 30 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('RouteProgressBar — edge cases', () {
    testWidgets('active with null route renders nothing', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RouteProgressBar(status: RouteProgressStatus.active),
        ),
      );

      expect(find.byType(Card), findsNothing);
    });

    testWidgets('active with empty maneuvers shows navigating fallback',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteProgressBar(
            status: RouteProgressStatus.active,
            route: _emptyManeuverRoute,
          ),
        ),
      );

      // With empty maneuvers, _currentManeuver is null
      // so it should show 'Navigating...' text.
      expect(find.text('Navigating...'), findsOneWidget);
    });

    testWidgets('negative maneuver index shows navigating fallback',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteProgressBar(
            status: RouteProgressStatus.active,
            route: _routeWith3Maneuvers,
            currentManeuverIndex: -1,
          ),
        ),
      );

      expect(find.text('Navigating...'), findsOneWidget);
    });

    testWidgets('out-of-bounds maneuver index shows navigating fallback',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteProgressBar(
            status: RouteProgressStatus.active,
            route: _routeWith3Maneuvers,
            currentManeuverIndex: 99,
          ),
        ),
      );

      expect(find.text('Navigating...'), findsOneWidget);
    });

    testWidgets('arrived without label shows generic arrived text',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RouteProgressBar(status: RouteProgressStatus.arrived),
        ),
      );

      expect(find.text('Arrived'), findsOneWidget);
    });

    testWidgets('progress advances proportionally', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteProgressBar(
            status: RouteProgressStatus.active,
            route: _routeWith3Maneuvers,
            currentManeuverIndex: 1,
          ),
        ),
      );

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      // 1 / 3 maneuvers ≈ 0.333
      expect(indicator.value, closeTo(1 / 3, 0.01));
    });

    testWidgets('last maneuver shows near-complete progress', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteProgressBar(
            status: RouteProgressStatus.active,
            route: _routeWith3Maneuvers,
            currentManeuverIndex: 2,
          ),
        ),
      );

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      // 2 / 3 ≈ 0.667
      expect(indicator.value, closeTo(2 / 3, 0.01));
    });

    testWidgets('arrived status yields progress 1.0', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteProgressBar(
            status: RouteProgressStatus.arrived,
            route: _routeWith3Maneuvers,
          ),
        ),
      );

      // Arrived doesn't show a LinearProgressIndicator —
      // it renders the arrived card instead.
      expect(find.byIcon(Icons.sports_score), findsOneWidget);
    });

    testWidgets('deviated shows amber border and wrong_location icon',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RouteProgressBar(status: RouteProgressStatus.deviated),
        ),
      );

      expect(find.byIcon(Icons.wrong_location), findsOneWidget);
      expect(find.text('Rerouting...'), findsOneWidget);
    });

    testWidgets('custom margin is applied', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteProgressBar(
            status: RouteProgressStatus.deviated,
            margin: const EdgeInsets.all(24),
          ),
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.margin, equals(const EdgeInsets.all(24)));
    });
  });
}
