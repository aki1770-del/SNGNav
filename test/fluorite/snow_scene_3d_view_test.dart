/// SnowScene3DView widget tests.
///
/// The first 3D-pixel widget is a CPU-projected perspective road-ahead scene
/// (CustomPainter, Skia Canvas) driven by `snow_rendering` data. These tests
/// pump the widget with two CONTRASTING conditions — clear vs severe (black
/// ice + whiteout) — and assert it builds and paints without throwing, and
/// that the two assessments actually differ (so the scene must visibly change).
///
/// Honest bound: a widget test asserts no-throw + that the driving data
/// differs; it does not capture pixels. Pixel-difference would need a golden
/// test, deliberately out of scope for the first pixel.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/fluorite/snow_scene_3d_view.dart';

void main() {
  // Clear: no precip, full visibility, +5°C → dry road, no fog, no particles.
  final clear = DrivingConditionAssessment.fromCondition(
    WeatherCondition.simulatedClear(timestamp: DateTime(2026, 1, 1)),
  );

  // Severe: heavy snow, freezing, ice risk, near-zero visibility → black ice
  // surface, dense fog (opacity 0.9), heavy particle count.
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

  Widget host(DrivingConditionAssessment a) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 480,
        child: SnowScene3DView(assessment: a),
      ),
    ),
  );

  testWidgets('builds and paints the CLEAR scene without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(host(clear));
    await tester.pump();
    expect(find.byType(SnowScene3DView), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds and paints the SEVERE scene without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(host(severe));
    await tester.pump();
    expect(find.byType(SnowScene3DView), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The severe scene (near-zero visibility + ice) is whiteout-class, so the
    // first-class response is to turn back — surfaced as the turn-back banner,
    // a real Text widget in the tree (unlike the canvas-painted advisory).
    expect(severe.recommendedResponse, RecommendedResponse.considerTurningBack);
    expect(find.textContaining('turning back'), findsOneWidget);
  });

  testWidgets('the CLEAR scene shows no turn-back banner', (tester) async {
    await tester.pumpWidget(host(clear));
    await tester.pump();
    expect(clear.recommendedResponse, RecommendedResponse.proceed);
    expect(find.textContaining('turning back'), findsNothing);
  });

  testWidgets(
    'the two conditions produce DIFFERENT driving data (scene must change)',
    (tester) async {
      // The painter repaints when the assessment differs; assert the inputs that
      // drive the scene actually contrast.
      expect(clear.surfaceState, RoadSurfaceState.dry);
      expect(severe.surfaceState, RoadSurfaceState.blackIce);
      // Nullable in snow_rendering 0.3.0: a road that could not be classified
      // has NO visibility model and NO precipitation model. These fixtures are
      // fully measured, so both are present — the `!` asserts exactly that.
      expect(clear.visibility!.opacity, 0.0); // no fog
      expect(severe.visibility!.opacity, greaterThan(0.5)); // heavy fog
      expect(clear.precipitation!.particleCount, 0); // no particles
      expect(severe.precipitation!.particleCount, greaterThan(0));
      expect(clear, isNot(equals(severe)));

      // And both render without throwing when swapped in place.
      await tester.pumpWidget(host(clear));
      await tester.pumpWidget(host(severe));
      expect(tester.takeException(), isNull);
    },
  );
}
