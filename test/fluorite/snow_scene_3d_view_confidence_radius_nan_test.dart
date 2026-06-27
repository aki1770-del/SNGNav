/// SnowScene3DView — confidence-radius NaN LOCK.
///
/// On the degraded-GPS compound-failure path the finiteness guards deliberately
/// preserve a valid coordinate carrying an UNKNOWN accuracy as the NaN sentinel
/// (see the L1/L2/L3 guards: an unknown accuracy is NOT a poison — the fix is
/// kept and flows to `degraded`). That NaN reaches this view through
/// `LocationState.confidenceRadius` (`position?.accuracy ?? 0.0`), and it drives
/// two rendered surfaces:
///
///   * the uncertainty-fog SCRIM opacity (snow_scene_3d_view.dart:188-192), via
///     `((accuracy - 50) / (500 - 50)).clamp(0,1)` → `_lerp(0.14, 0.62, u)`;
///   * the degrade-banner LABEL (snow_scene_3d_view.dart:230-232), via
///     `accuracy > 0 ? '  ±${accuracy.toStringAsFixed(0)} m' : ''`.
///
/// Both are currently NaN-SAFE only incidentally:
///   * `NaN.clamp(0,1)` returns 1.0 in Dart (NaN sorts above the upper limit),
///     so `u` saturates to max-fog and the scrim opacity stays FINITE (0.62) —
///     the honest "as uncertain as it gets" reading, never a broken/garbage
///     scrim that flutter would fail to paint;
///   * `NaN > 0` is false, so the label is SUPPRESSED (empty) — HER never sees a
///     nonsensical "±NaN m".
///
/// These tests LOCK that behavior so it is ENFORCED, not accidental: a future
/// refactor of the clamp/label expressions that reintroduced a non-finite scrim
/// opacity or a literal "±NaN m" string would break here. They go-and-SEE the
/// rendered widget (OPS-066 observation-grade), not just the arithmetic.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/bloc/bloc.dart';
import 'package:sngnav_snow_scene/fluorite/snow_scene_3d_view.dart';

void main() {
  // A clear, proceed-class assessment so NO turn-back banner is present: the
  // honest GPS-degradation overlay (fog scrim + degrade banner) renders on its
  // own and can be observed in isolation.
  final clear = DrivingConditionAssessment.fromCondition(
    WeatherCondition.clear(timestamp: DateTime(2026, 1, 1)),
  );

  // A degraded location whose coordinate is VALID (finite, map-placeable) but
  // whose accuracy is the UNKNOWN sentinel (NaN) — exactly what the finiteness
  // guards preserve and forward. confidenceRadius == NaN.
  final nanRadius = LocationState(
    quality: LocationQuality.degraded,
    position: GeoPosition(
      latitude: 35.1709, // Nagoya — a real, placeable point
      longitude: 136.8815,
      accuracy: double.nan, // unknown accuracy → confidenceRadius is NaN
      timestamp: DateTime(2026, 1, 1),
    ),
  );

  Widget host(LocationState location) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 480,
            child: SnowScene3DView(assessment: clear, location: location),
          ),
        ),
      );

  // The uncertainty-fog scrim base colour (snow_scene_3d_view.dart:202).
  const scrimBase = Color(0xFFE9EEF2);
  bool rgbMatches(Color c) =>
      (c.r - scrimBase.r).abs() < 0.01 &&
      (c.g - scrimBase.g).abs() < 0.01 &&
      (c.b - scrimBase.b).abs() < 0.01;

  testWidgets(
      'a NaN confidenceRadius renders a FINITE scrim opacity (clamp -> max-fog)',
      (tester) async {
    await tester.pumpWidget(host(nanRadius));
    await tester.pump();

    // The view built and painted — a non-finite opacity would have produced a
    // broken/garbage scrim, not a clean render.
    expect(tester.takeException(), isNull);

    // Locate the fog scrim by its base colour and read the ACTUAL rendered
    // alpha the driver sees.
    final scrims = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .map((b) => b.color)
        .whereType<Color>()
        .where(rgbMatches)
        .toList();

    expect(scrims, isNotEmpty,
        reason: 'the uncertainty-fog scrim must be rendered for a degraded fix');
    for (final c in scrims) {
      expect(c.a.isFinite, isTrue,
          reason: 'a NaN confidenceRadius must NOT yield a non-finite scrim '
              'opacity — the scene must degrade honestly, not break');
      // NaN clamps the uncertainty to 1.0 → max fog (_lerp(0.14, 0.62, 1.0)).
      expect(c.a, closeTo(0.62, 0.001),
          reason: 'an unknown (NaN) confidence radius reads as MAX uncertainty '
              '(thickest fog), never as a clear/confident scene');
    }
  });

  testWidgets(
      'a NaN confidenceRadius SUPPRESSES the ±N m label (never shows "±NaN m")',
      (tester) async {
    await tester.pumpWidget(host(nanRadius));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The degrade banner is present (a degraded fix), but it carries NO numeric
    // accuracy suffix — HER must never read a nonsensical "±NaN m".
    expect(find.textContaining('NaN'), findsNothing,
        reason: 'a NaN confidence radius must never be rendered as text');
    expect(find.textContaining('±'), findsNothing,
        reason: 'the ±N m suffix must be suppressed for an unknown radius');

    // And the honest base banner IS shown (the overlay did render).
    expect(find.textContaining('GPS degraded'), findsOneWidget,
        reason: 'the degrade banner must still tell HER the position is '
            'approximate, just without a bogus number');
  });

  testWidgets(
      'a FINITE confidence radius STILL renders the ±N m label '
      '(the suppression is NaN-specific, not a blanket drop)',
      (tester) async {
    final finiteRadius = LocationState(
      quality: LocationQuality.degraded,
      position: GeoPosition(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracy: 220.0, // a real, large-but-finite radius
        timestamp: DateTime(2026, 1, 1),
      ),
    );

    await tester.pumpWidget(host(finiteRadius));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Regression guard: a known radius MUST still surface its number, so the
    // NaN-suppression above cannot silently swallow real accuracy data.
    expect(find.textContaining('±220 m'), findsOneWidget);
  });
}
