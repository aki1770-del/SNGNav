import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sngnav_snow_scene/bloc/navigation_bloc.dart';
import 'package:sngnav_snow_scene/bloc/navigation_event.dart';
import 'package:sngnav_snow_scene/bloc/navigation_state.dart';
import 'package:sngnav_snow_scene/models/route_result.dart';
import 'package:sngnav_snow_scene/widgets/route_progress_bar.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _nagoya = const LatLng(35.1709, 136.8815);
final _inuyama = const LatLng(35.3886, 136.9444);

RouteResult _testRoute() => RouteResult(
      shape: [_nagoya, _inuyama],
      maneuvers: [
        RouteManeuver(
          index: 0,
          instruction: 'Depart north on Route 41',
          type: 'depart',
          lengthKm: 1.2,
          timeSeconds: 120,
          position: _nagoya,
        ),
        RouteManeuver(
          index: 1,
          instruction: 'Turn right onto Route 153',
          type: 'right',
          lengthKm: 0.8,
          timeSeconds: 60,
          position: const LatLng(35.2, 136.9),
        ),
        RouteManeuver(
          index: 2,
          instruction: 'Arrive at Inuyama Castle',
          type: 'arrive',
          lengthKm: 0.0,
          timeSeconds: 0,
          position: _inuyama,
        ),
      ],
      totalDistanceKm: 4.2,
      totalTimeSeconds: 720, // 12 min
      summary: 'Route 41 → Route 153',
      engineInfo: const EngineInfo(name: 'mock'),
    );

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildWidget(NavigationBloc bloc) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<NavigationBloc>.value(
        value: bloc,
        child: const RouteProgressBar(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RouteProgressBar', () {
    late MockNavigationBloc bloc;

    setUp(() {
      bloc = MockNavigationBloc();
    });

    testWidgets('renders nothing when navigation is idle', (tester) async {
      when(() => bloc.state).thenReturn(const NavigationState.idle());

      await tester.pumpWidget(_buildWidget(bloc));

      // SizedBox.shrink has zero size.
      expect(find.byType(RouteProgressBar), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows current maneuver instruction when navigating',
        (tester) async {
      final route = _testRoute();
      when(() => bloc.state).thenReturn(NavigationState(
        status: NavigationStatus.navigating,
        route: route,
        currentManeuverIndex: 0,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Depart north on Route 41'), findsOneWidget);
    });

    testWidgets('shows correct icon for maneuver type', (tester) async {
      final route = _testRoute();
      when(() => bloc.state).thenReturn(NavigationState(
        status: NavigationStatus.navigating,
        route: route,
        currentManeuverIndex: 1, // "right" type
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.byIcon(Icons.turn_right), findsOneWidget);
    });

    testWidgets('shows distance for current maneuver', (tester) async {
      final route = _testRoute();
      when(() => bloc.state).thenReturn(NavigationState(
        status: NavigationStatus.navigating,
        route: route,
        currentManeuverIndex: 1,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('0.8 km'), findsOneWidget);
    });

    testWidgets('shows ETA and total distance', (tester) async {
      final route = _testRoute();
      when(() => bloc.state).thenReturn(NavigationState(
        status: NavigationStatus.navigating,
        route: route,
        currentManeuverIndex: 0,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('12 min'), findsOneWidget);
      expect(find.text('4.2 km'), findsOneWidget);
    });

    testWidgets('shows progress bar with correct value', (tester) async {
      final route = _testRoute();
      // Index 1 of 3 maneuvers => progress = 1/3 ≈ 0.333
      when(() => bloc.state).thenReturn(NavigationState(
        status: NavigationStatus.navigating,
        route: route,
        currentManeuverIndex: 1,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(1 / 3, 0.01));
    });

    testWidgets('shows "Rerouting..." text when deviated', (tester) async {
      final route = _testRoute();
      when(() => bloc.state).thenReturn(NavigationState(
        status: NavigationStatus.deviated,
        route: route,
        currentManeuverIndex: 1,
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Rerouting...'), findsOneWidget);
      expect(find.byIcon(Icons.wrong_location), findsOneWidget);
    });

    testWidgets('shows arrived card with destination label', (tester) async {
      final route = _testRoute();
      when(() => bloc.state).thenReturn(NavigationState(
        status: NavigationStatus.arrived,
        route: route,
        currentManeuverIndex: 2,
        destinationLabel: 'Inuyama Castle',
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('Arrived at Inuyama Castle'), findsOneWidget);
      expect(find.byIcon(Icons.sports_score), findsOneWidget);
    });
  });
}
