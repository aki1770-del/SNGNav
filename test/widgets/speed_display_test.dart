import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sngnav_snow_scene/bloc/location_bloc.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/widgets/speed_display.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

GeoPosition _position({
  double speed = 18.6, // m/s => 66.96 km/h => rounds to 67
  double accuracy = 5.0,
}) {
  return GeoPosition(
    latitude: 35.1709,
    longitude: 136.8815,
    accuracy: accuracy,
    speed: speed,
    heading: 90.0,
    timestamp: DateTime(2026, 2, 27),
  );
}

Widget _buildWidget(LocationBloc bloc) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<LocationBloc>.value(
        value: bloc,
        child: const SpeedDisplay(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SpeedDisplay', () {
    late MockLocationBloc bloc;

    setUp(() {
      bloc = MockLocationBloc();
    });

    testWidgets('renders "--" when LocationState is uninitialized',
        (tester) async {
      when(() => bloc.state).thenReturn(const LocationState.uninitialized());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('--'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);
    });

    testWidgets('renders "--" when speed is NaN', (tester) async {
      when(() => bloc.state).thenReturn(LocationState(
        quality: LocationQuality.fix,
        position: GeoPosition(
          latitude: 35.1709,
          longitude: 136.8815,
          accuracy: 5.0,
          speed: double.nan,
          heading: 0.0,
          timestamp: DateTime(2026, 2, 27),
        ),
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('--'), findsOneWidget);
    });

    testWidgets('renders rounded speed when valid', (tester) async {
      // 18.6 m/s * 3.6 = 66.96 km/h => rounds to 67.
      when(() => bloc.state).thenReturn(LocationState(
        quality: LocationQuality.fix,
        position: _position(speed: 18.6),
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('67'), findsOneWidget);
    });

    testWidgets('renders "km/h" unit label', (tester) async {
      when(() => bloc.state).thenReturn(const LocationState.uninitialized());

      await tester.pumpWidget(_buildWidget(bloc));

      expect(find.text('km/h'), findsOneWidget);
    });

    testWidgets('shows green dot when quality is fix', (tester) async {
      when(() => bloc.state).thenReturn(LocationState(
        quality: LocationQuality.fix,
        position: _position(),
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      final dot = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      final decoration = dot.decoration! as BoxDecoration;
      expect(decoration.color, Colors.green);
    });

    testWidgets('shows amber dot when quality is degraded', (tester) async {
      when(() => bloc.state).thenReturn(LocationState(
        quality: LocationQuality.degraded,
        position: _position(accuracy: 100.0),
      ));

      await tester.pumpWidget(_buildWidget(bloc));

      final dot = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      final decoration = dot.decoration! as BoxDecoration;
      expect(decoration.color, Colors.amber);
    });
  });
}
