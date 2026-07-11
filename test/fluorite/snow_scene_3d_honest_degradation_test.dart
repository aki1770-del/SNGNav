/// SnowScene3DView honest-degradation tests.
///
/// The 3D forward-view is driven by weather alone — it does not know where the
/// driver is. Fed a [LocationState], it must DEGRADE HONESTLY when GPS is lost:
///   * navigation-grade fix → no degradation overlay (confident scene);
///   * dead reckoning / degraded → a "GPS lost — position estimated" banner;
///   * error / DR 500 m safety cap exceeded → an explicit "POSITION
///     UNAVAILABLE" floor instead of a confident road.
///
/// Honest bound: these assert the WIDGET TREE (banner/floor text presence and
/// absence), not pixels. The uncertainty-fog scrim is asserted structurally
/// (it is keyed off the same LocationState the banner is).
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/fluorite/snow_scene_3d_view.dart';

void main() {
  // A severe-but-confident driving picture: the scene itself is "dangerous"
  // (black ice, whiteout) but the POSITION is known. Degradation must come
  // from the location signal, not the weather.
  final severe = DrivingConditionAssessment.fromCondition(
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -8,
      visibilityMeters: 60,
      windSpeedKmh: 45,
      iceRisk: true,
      timestamp: DateTime(2026, 1, 1),
      source: ObservationSource.measured,
    ),
  );

  GeoPosition pos(double accuracy) => GeoPosition(
    latitude: 35.17,
    longitude: 136.88,
    accuracy: accuracy,
    speed: 14,
    heading: 90,
    timestamp: DateTime(2026, 1, 1, 7, 15),
  );

  Widget host(LocationState? location) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 480,
        child: SnowScene3DView(assessment: severe, location: location),
      ),
    ),
  );

  testWidgets('FIX: navigation-grade fix shows NO degradation overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(LocationState(quality: LocationQuality.fix, position: pos(8))),
    );
    await tester.pump();

    expect(find.byType(SnowScene3DView), findsOneWidget);
    expect(find.textContaining('position estimated'), findsNothing);
    expect(find.text('POSITION UNAVAILABLE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FIX (null location) also shows NO degradation overlay', (
    tester,
  ) async {
    await tester.pumpWidget(host(null));
    await tester.pump();

    expect(find.textContaining('position estimated'), findsNothing);
    expect(find.text('POSITION UNAVAILABLE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'DEAD RECKONING: shows "GPS lost — position estimated" + accuracy',
    (tester) async {
      await tester.pumpWidget(
        host(
          LocationState(
            quality: LocationQuality.degraded,
            isDeadReckoning: true,
            position: pos(220),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('GPS lost — position estimated'),
        findsOneWidget,
      );
      expect(find.textContaining('±220 m'), findsOneWidget);
      // Not the unavailable floor — a usable (if uncertain) position remains.
      expect(find.text('POSITION UNAVAILABLE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DEGRADED (not DR): shows "position approximate" banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        LocationState(quality: LocationQuality.degraded, position: pos(120)),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('GPS degraded — position approximate'),
      findsOneWidget,
    );
    expect(find.textContaining('±120 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ERROR (DR 500m cap exceeded): shows POSITION UNAVAILABLE floor',
    (tester) async {
      await tester.pumpWidget(
        host(
          const LocationState(
            quality: LocationQuality.error,
            errorMessage: 'Dead reckoning exceeded 500 m safety cap',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('POSITION UNAVAILABLE'), findsOneWidget);
      expect(find.textContaining('safety cap'), findsOneWidget);
      // The confident-road banner must NOT be shown alongside the floor.
      expect(find.textContaining('position estimated'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uncertainty scrim thickens with accuracy (220m > 80m)', (
    tester,
  ) async {
    // Pull the scrim opacity out of the rendered DecoratedBox for each
    // accuracy; the worse fix must produce the heavier (more opaque) scrim.
    Future<double> scrimAlphaFor(double accuracy) async {
      await tester.pumpWidget(
        host(
          LocationState(
            quality: LocationQuality.degraded,
            isDeadReckoning: true,
            position: pos(accuracy),
          ),
        ),
      );
      await tester.pump();
      // The uncertainty fog is the white (RGB 0xE9EEF2) DecoratedBox scrim.
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .where((d) {
            final c = d.color;
            return c != null && (c.toARGB32() & 0x00FFFFFF) == 0xE9EEF2;
          })
          .toList();
      expect(
        boxes,
        isNotEmpty,
        reason: 'uncertainty fog scrim must be present',
      );
      return boxes.first.color!.a;
    }

    final near = await scrimAlphaFor(80);
    final far = await scrimAlphaFor(220);
    expect(
      far,
      greaterThan(near),
      reason: 'larger confidence radius → thicker uncertainty fog',
    );
  });
}
