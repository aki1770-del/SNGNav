/// Pixel-capture harness for the honest-degradation 3D scene.
///
/// Renders SnowScene3DView at three location qualities (fix / dead-reckoning /
/// position-unavailable) over an identical severe weather picture, and writes
/// real PNGs to test/fluorite/_capture/ so a human can eyeball the degradation.
/// Asserts the captured bytes are non-empty PNGs of the expected size.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/fluorite/snow_scene_3d_view.dart';

void main() {
  final severe = DrivingConditionAssessment.fromCondition(
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -8,
      visibilityMeters: 80,
      windSpeedKmh: 45,
      iceRisk: true,
      timestamp: DateTime(2026, 1, 1),
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

  final cases = <String, LocationState?>{
    'fix': LocationState(quality: LocationQuality.fix, position: pos(8)),
    'dead_reckoning': LocationState(
      quality: LocationQuality.degraded,
      isDeadReckoning: true,
      position: pos(220),
    ),
    'position_unavailable': const LocationState(
      quality: LocationQuality.error,
      errorMessage: 'Dead reckoning exceeded 500 m safety cap',
    ),
  };

  for (final entry in cases.entries) {
    testWidgets('capture: ${entry.key}', (tester) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 800,
                  height: 480,
                  child: SnowScene3DView(
                    assessment: severe,
                    location: entry.value,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        final dir = Directory('test/fluorite/_capture')..createSync();
        final file = File('${dir.path}/scene_${entry.key}.png');
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        expect(file.lengthSync(), greaterThan(0));
        expect(image.width, 800);
        expect(image.height, 480);
        // Log so the raw path + byte count appear in test output.
        // ignore: avoid_print
        print('CAPTURE ${entry.key}: ${file.path} '
            '${file.lengthSync()} bytes ${image.width}x${image.height}');
      });

      expect(tester.takeException(), isNull);
    });
  }
}
